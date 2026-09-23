#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["textual>=8.0"]
# ///
"""The hand-off queue, stored as markdown notes in a zk notebook.

An item is one thing the user must personally type, click, or approve. Agents
add items; only the user closes them.

Replaces the SQLite-backed `ask`. Same verbs, flags, and exit codes, so old
callers work without changes. The difference: items live as one markdown file
each, editable in any markdown editor, synced by git.

State lives in ONE place: the `- [ ]` / `- [x]` checkbox. Not a frontmatter
key (zk cannot filter on frontmatter). Not a `#open` tag (that would duplicate
the checkbox). `#ask` marks the note as a queue item; it does not show whether
the item is open.

Two zk traps this file works around:

  * `zk new` silently discards the body unless you pass --interactive.
    This script writes notes directly, then runs `zk index`.
  * A `#tag` at column 0 parses as a heading, not a tag. Every tag here
    is inline, on the checkbox line.

One directory trap: cwd auto-discovery overrides ZK_NOTEBOOK_DIR, so the
notebook path is always explicit. Never rely on the environment variable.

Without an argument, a terminal gets the TUI. A pipe, hook, status line, or
agent gets the text list. The test is whether stdin and stdout are both a
terminal, so no existing caller has to change. `--plain`, `--no-tui`, and
`ASK_NO_TUI=1` each force the text path.

The TUI never probes on startup. The old default ran every `--verify` command
before printing a line. Each probe costs up to VERIFY_TIMEOUT seconds; across
hundreds of items that is minutes. Probes now run only on request, in
background threads.
"""

import argparse
import json
import os
import random
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# The Nix wrapper sets ASK_NOTEBOOK from `programs.ask-zk.notebook`. The
# fallback below applies only when the script runs outside that wrapper.
#
# ZK_NOTEBOOK_DIR is deliberately not read here. zk's cwd auto-discovery
# overrides that variable, so an agent inside a different notebook would write
# items to the wrong place.
NOTEBOOK = Path(os.environ.get("ASK_NOTEBOOK", Path.home() / "notes"))
STALE_DAYS = int(os.environ.get("ASK_STALE_DAYS", "7"))
VERIFY_TIMEOUT = 8  # seconds; a probe that hangs must not hang the list
# Seconds between TUI checks for added, edited, or removed notes.
# 0 turns the check off; R still reloads by hand.
POLL_SECONDS = float(os.environ.get("ASK_TUI_POLL", "5"))

ID_CHARSET = "abcdefghijklmnopqrstuvwxyz0123456789"  # zk: alphanum, lower
ID_LEN = 4

TAG_OK = re.compile(r"[^a-z0-9_-]")
OPEN_BOX = re.compile(r"^- \[ \] ")
DONE_BOX = re.compile(r"^- \[x\] ", re.I)

# The checkbox and frontmatter sit near the top of each file. Anything below
# this line count is body prose that cannot change state -- reading further
# wastes I/O across 300 notes.
HEAD_LINES = 30


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def clean_tag(tag: str) -> str | None:
    t = TAG_OK.sub("-", tag.strip().lower()).strip("-")
    return t or None


# --------------------------------------------------------------------------
# reading


def parse(path: Path) -> dict | None:
    """One item, or None when the note is not a hand-off item.

    Cheap on purpose: only the head of the file decides state.
    """
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    lines = text.splitlines()

    front: dict[str, str] = {}
    if lines and lines[0].strip() == "---":
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == "---":
                break
            if ": " in line:
                k, _, v = line.partition(": ")
                front[k.strip()] = v.strip()

    state = None
    what = ""
    tags: list[str] = []
    for line in lines[:HEAD_LINES]:
        if OPEN_BOX.match(line):
            state, rest = "open", line[6:]
        elif DONE_BOX.match(line):
            state, rest = front.get("closed", "done"), line[6:]
        else:
            continue
        tags = re.findall(r"(?<!\S)#([a-z0-9_-]+)", rest)
        if "ask" not in tags:
            state = None
            continue
        what = re.sub(r"(?<!\S)#[a-z0-9_-]+", "", rest).strip()
        break

    if state is None:
        return None

    created = front.get("created", "")
    age = 0.0
    if created:
        try:
            then = datetime.strptime(created, "%Y-%m-%dT%H:%M:%SZ").replace(
                tzinfo=timezone.utc
            )
            age = (datetime.now(timezone.utc) - then).total_seconds() / 86400
        except ValueError:
            pass

    body = "\n".join(lines)
    return {
        "id": path.stem,
        "ask_id": front.get("ask_id", ""),
        "path": path,
        "state": state,
        "what": what,
        "why": section(body, "Why"),
        "cwd": front.get("cwd", ""),
        "by": front.get("by", ""),
        "created": created,
        "age_days": age,
        "tags": [t for t in tags if t != "ask"],
        "cmd": fenced(body, "Do this"),
        "verify": fenced(body, "Done when"),
    }


def fenced(body: str, heading: str) -> str:
    """The shell inside the fenced block under `## <heading>`."""
    m = re.search(
        rf"^## {re.escape(heading)}\s*$(.*?)^```\w*\s*$(.*?)^```\s*$",
        body,
        re.M | re.S,
    )
    return m.group(2).strip() if m else ""


def section(body: str, heading: str) -> str:
    m = re.search(rf"^## {re.escape(heading)}\s*$(.*?)(?=^## |\Z)", body, re.M | re.S)
    return m.group(1).strip() if m else ""


def notebook_stamp() -> tuple[int, int]:
    """Return (count of *.md notes, newest mtime in ns).

    An add or remove changes the count; an edit changes the newest mtime.
    The TUI compares stamps to skip a full parse when nothing changed.
    """
    count, newest = 0, 0
    with os.scandir(NOTEBOOK) as it:
        for e in it:
            if e.name.endswith(".md") and e.is_file():
                count += 1
                newest = max(newest, e.stat().st_mtime_ns)
    return count, newest


def load_all() -> list[dict]:
    items = [parse(p) for p in sorted(NOTEBOOK.glob("*.md"))]
    items = [i for i in items if i]
    items.sort(key=lambda i: i["created"] or "9999")
    return items


def resolve(items: list[dict], token: str) -> dict | None:
    """A note id, an unambiguous prefix, a legacy ask id, or a list position."""
    for i in items:
        if i["id"] == token or i["ask_id"] == token:
            return i
    if token.isdigit():
        n = int(token)
        openish = [i for i in items if i["state"] == "open"]
        if 1 <= n <= len(openish):
            return openish[n - 1]
    hits = [i for i in items if i["id"].startswith(token) or i["ask_id"].startswith(token)]
    return hits[0] if len(hits) == 1 else None


# --------------------------------------------------------------------------
# writing


def new_id(taken: set[str]) -> str:
    while True:
        iid = "".join(random.choice(ID_CHARSET) for _ in range(ID_LEN))
        if iid not in taken:
            return iid


def reindex() -> None:
    """Keep zk's index current. A no-op reindex costs tens of ms.

    Failure is not fatal: notes on disk are the real store, and every read
    path in this file scans files, not the index.
    """
    try:
        subprocess.run(
            ["zk", "index", "--notebook-dir", str(NOTEBOOK), "--no-input", "--quiet"],
            capture_output=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def cmd_add(args: argparse.Namespace) -> int:
    what = " ".join(args.what.split())
    tags = ["ask"] + [t for t in (clean_tag(x) for x in (args.tag or [])) if t]
    iid = new_id({p.stem for p in NOTEBOOK.glob("*.md")})

    front = [f"created: {now_iso()}"]
    if args.cwd:
        front.append(f"cwd: {args.cwd}")
    by = args.by or os.environ.get("ASK_BY") or os.environ.get("USER", "")
    if by:
        front.append(f"by: {by}")

    out = ["---", *front, "---", "", f"# {what}", ""]
    out.append(f"- [ ] {what}  " + " ".join(f"#{t}" for t in tags))
    out.append("")
    if args.why:
        out += ["## Why", "", args.why.strip(), ""]
    if args.cmd:
        out += ["## Do this", "", "```bash", *args.cmd, "```", ""]
    if args.verify:
        out += [
            "## Done when",
            "",
            "This command exits 0:",
            "",
            "```bash",
            args.verify.strip(),
            "```",
            "",
        ]

    (NOTEBOOK / f"{iid}.md").write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
    reindex()
    if not args.quiet:
        print(iid)
    return 0


def close(item: dict, verb: str) -> None:
    """Tick the box. The checkbox is the state; the frontmatter only records
    which kind of close it was, for the reader."""
    lines = item["path"].read_text(encoding="utf-8").splitlines()
    for n, line in enumerate(lines):
        if OPEN_BOX.match(line):
            lines[n] = "- [x] " + line[6:]
            break
    if lines and lines[0].strip() == "---":
        end = next(
            (i for i, l in enumerate(lines[1:], 1) if l.strip() == "---"), 1
        )
        lines[end:end] = [f"closed: {verb}", f"closed_ts: {now_iso()}"]
    item["path"].write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd_close(args: argparse.Namespace) -> int:
    items = load_all()
    it = resolve(items, args.id)
    if not it:
        print(f"ask: no item matches {args.id!r}", file=sys.stderr)
        return 1
    if it["state"] != "open":
        print(f"{it['id']} is already {it['state']}")
        return 0
    close(it, args.verb)
    reindex()
    print(f"{it['id']} {args.verb}")
    return 0


# --------------------------------------------------------------------------
# probes


def probe(item: dict) -> bool:
    """True when the verify command says the item is already handled."""
    if not item["verify"]:
        return False
    try:
        r = subprocess.run(
            item["verify"],
            shell=True,
            capture_output=True,
            timeout=VERIFY_TIMEOUT,
            cwd=item["cwd"] or None,
        )
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


# --------------------------------------------------------------------------
# output


def age_label(days: float) -> str:
    if days < 1 / 24:
        return f"{int(days * 1440)}m"
    if days < 1:
        return f"{int(days * 24)}h"
    return f"{int(days)}d"


def select(items: list[dict], args: argparse.Namespace) -> list[dict]:
    out = items
    if getattr(args, "tag", None):
        want = {clean_tag(t) for t in args.tag}
        out = [i for i in out if want <= set(i["tags"])]
    if getattr(args, "cwd", None):
        out = [i for i in out if i["cwd"] == args.cwd]
    if getattr(args, "all", False):
        return out
    if getattr(args, "closed", False):
        return [i for i in out if i["state"] != "open"]
    return [i for i in out if i["state"] == "open"]


def cmd_list(args: argparse.Namespace) -> int:
    items = select(load_all(), args)
    if not args.no_verify:
        for it in list(items):
            if it["state"] == "open" and probe(it):
                close(it, "done")
                it["state"] = "done"
        items = select(load_all(), args)
    if args.plain:
        for it in items:
            print(f"{it['id']}\t{age_label(it['age_days'])}\t{it['state']}\t{it['what']}")
        return 0
    if not items:
        print("nothing waiting on you")
        return 0
    for n, it in enumerate(items, 1):
        mark = "!" if it["age_days"] >= STALE_DAYS else " "
        print(f"{mark}{n:>3}. {it['id']}  {age_label(it['age_days']):>4}  {it['what']}")
        if it["why"]:
            print(f"        why: {' '.join(it['why'].split())[:160]}")
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    it = resolve(load_all(), args.id)
    if not it:
        print(f"ask: no item matches {args.id!r}", file=sys.stderr)
        return 1
    print(it["path"].read_text(encoding="utf-8"), end="")
    return 0


def cmd_count(args: argparse.Namespace) -> int:
    items = [i for i in load_all() if i["state"] == "open"]
    print(len(items))
    # Exit 3 == "something in here is stale". A bare integer cannot say that,
    # and argparse already owns exit 2 for usage errors. Callers treat 3 as a
    # signal, never as a failure.
    return 3 if any(i["age_days"] >= STALE_DAYS for i in items) else 0


def cmd_sweep(args: argparse.Namespace) -> int:
    closed = 0
    for it in load_all():
        if it["state"] == "open" and probe(it):
            close(it, "done")
            print(f"{it['id']} done (verify passed)")
            closed += 1
    if closed:
        reindex()
    print(f"{closed} closed")
    return 0


def cmd_search(args: argparse.Namespace) -> int:
    needle = args.term.lower()
    for it in load_all():
        hay = f"{it['what']} {it['why']} {it['cmd']}".lower()
        if needle in hay:
            print(f"{it['id']}\t{it['state']}\t{it['what']}")
    return 0


def cmd_note(args: argparse.Namespace) -> int:
    it = resolve(load_all(), args.id)
    if not it:
        print(f"ask: no item matches {args.id!r}", file=sys.stderr)
        return 1
    text = it["path"].read_text(encoding="utf-8").rstrip("\n")
    if "\n## Notes" not in text:
        text += "\n\n## Notes\n"
    text += f"\n- {now_iso()} -- {' '.join(args.text)}\n"
    it["path"].write_text(text, encoding="utf-8")
    reindex()
    print(f"{it['id']} noted")
    return 0


def cmd_log(args: argparse.Namespace) -> int:
    for it in load_all():
        rec = {k: v for k, v in it.items() if k != "path" and v not in ("", [], 0.0)}
        print(json.dumps(rec, ensure_ascii=False))
    return 0


def cmd_db(args: argparse.Namespace) -> int:
    print(NOTEBOOK)
    return 0


def cmd_tag(args: argparse.Namespace) -> int:
    if not args.id:
        seen: dict[str, int] = {}
        for it in load_all():
            if it["state"] == "open":
                for t in it["tags"]:
                    seen[t] = seen.get(t, 0) + 1
        for t, n in sorted(seen.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"{n:>4}  {t}")
        return 0
    it = resolve(load_all(), args.id)
    if not it:
        print(f"ask: no item matches {args.id!r}", file=sys.stderr)
        return 1
    add = [t for t in (clean_tag(x) for x in args.tags) if t and t not in it["tags"]]
    if not add:
        return 0
    lines = it["path"].read_text(encoding="utf-8").splitlines()
    for n, line in enumerate(lines):
        if OPEN_BOX.match(line) or DONE_BOX.match(line):
            lines[n] = line.rstrip() + " " + " ".join(f"#{t}" for t in add)
            break
    it["path"].write_text("\n".join(lines) + "\n", encoding="utf-8")
    reindex()
    print(f"{it['id']} +{' +'.join(add)}")
    return 0


# --------------------------------------------------------------------------
# TUI
#
# Textual is imported here, not at module scope, because every other verb must
# stay fast. `add`, `count` and `sweep` run from agents and from loops; they
# must not pay for a UI toolkit they never build.

HELP_TEXT = """\
[b]Move[/b]
  j / k / arrows   up and down          g / G   first / last
  enter            show the note        tab     move between panes

[b]Choose[/b]
  space            select or deselect this item
  escape           clear the selection

[b]Act[/b]  (on the selection, or on the item under the cursor)
  d                tick the box: done
  x                tick the box: drop
  u                undo the last close
  r                run the "Do this" command, in the item's directory
  v                run the "Done when" probe        V   probe all shown
  o                open the note in $EDITOR         O   reveal in Obsidian
  n                add a line to "## Notes"
  y                yank this item's id to the clipboard

[b]Filter[/b]
  /                filter by text       t   filter by tag
  a                show closed items too
  C                clear every filter
  R                read the notebook again. The list also
                   reloads when a note changes, unless ASK_TUI_POLL=0

  The previous filter returns selected. Type to replace it,
  press End to edit it.

[b]Leave[/b]
  q                quit                 ?   this help
"""


def copy_to_system_clipboard(text: str) -> bool:
    """Put text on the OS clipboard. True if a copier took it.

    Tries macOS first, then the two usual Linux copiers, so the same
    build works on a remote box.
    """
    for argv in (["pbcopy"], ["wl-copy"], ["xclip", "-selection", "clipboard"]):
        try:
            subprocess.run(argv, input=text, text=True, check=True)
            return True
        except (OSError, subprocess.SubprocessError):
            continue
    return False


def run_cmd_in_terminal(cmd: str, cwd: str) -> int:
    """Run a shell command with full terminal control.

    The command can ask for TouchID, open a browser, or draw its own UI.
    The caller must release the screen first -- see App.suspend.
    """
    print(f"\n\033[1m$ {cmd}\033[0m\n", flush=True)
    try:
        rc = subprocess.run(["bash", "-c", cmd], cwd=cwd or None).returncode
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"could not run it: {exc}")
        rc = 127
    print(f"\n\033[2m[exit {rc}] press enter\033[0m", flush=True)
    try:
        input()
    except EOFError:
        pass
    return rc


def build_app_class():
    """Define the app once Textual is known to be importable."""
    from rich.text import Text
    from textual import work
    from textual.app import App, ComposeResult
    from textual.binding import Binding
    from textual.containers import Vertical, VerticalScroll
    from textual.screen import ModalScreen
    from textual.widgets import DataTable, Footer, Input, Static

    class Confirm(ModalScreen[bool]):
        """A yes/no gate. Keys only -- the hands are already on the keyboard."""

        BINDINGS = [
            Binding("y", "yes", "yes"),
            Binding("n,escape,q", "no", "no"),
        ]

        def __init__(self, question: str) -> None:
            super().__init__()
            self.question = question

        def compose(self) -> ComposeResult:
            yield Static(f"{self.question}\n\n[b]y[/b] yes    [b]n[/b] no", id="ask")

        def action_yes(self) -> None:
            self.dismiss(True)

        def action_no(self) -> None:
            self.dismiss(False)

    class Help(ModalScreen[None]):
        BINDINGS = [Binding("escape,q,question_mark,space", "close", "close")]

        def compose(self) -> ComposeResult:
            yield Static(HELP_TEXT, id="help")

        def action_close(self) -> None:
            self.dismiss(None)

    class AskApp(App):
        TITLE = "ask-zk"
        CSS = """
        Screen { layers: base overlay; }
        #summary { height: 1; padding: 0 1; background: $panel; color: $text-muted; }
        #items { height: 1fr; }
        #detail { height: 40%; border-top: solid $primary; padding: 0 1; }
        #prompt { display: none; dock: bottom; }
        #prompt.on { display: block; }
        Confirm { align: center middle; }
        #ask { padding: 1 2; width: 60; border: thick $warning; background: $surface; }
        Help { align: center middle; }
        #help { padding: 1 2; width: 78; border: thick $primary; background: $surface; }
        """
        BINDINGS = [
            Binding("q", "quit", "quit"),
            Binding("question_mark", "help", "help", key_display="?"),
            Binding("d", "close_done", "done"),
            Binding("x", "close_drop", "drop"),
            Binding("u", "undo", "undo"),
            Binding("r", "run", "run"),
            Binding("v", "verify", "verify"),
            Binding("V", "verify_all", "verify shown", show=False),
            Binding("o", "edit", "edit"),
            Binding("y", "yank", "yank"),
            Binding("O", "obsidian", "obsidian", show=False),
            Binding("n", "note", "note", show=False),
            Binding("slash", "filter", "filter", key_display="/"),
            Binding("t", "tag_filter", "tag", show=False),
            Binding("a", "toggle_closed", "closed", show=False),
            Binding("C", "clear_filters", "clear filters", show=False),
            Binding("R", "reload", "reload", show=False),
            Binding("space", "select", "select", show=False),
            Binding("escape", "clear_selection", "clear", show=False),
            Binding("g", "top", "top", show=False),
            Binding("G", "bottom", "bottom", show=False),
            Binding("j", "cursor_down", "down", show=False),
            Binding("k", "cursor_up", "up", show=False),
        ]

        def __init__(self, tags: list[str] | None, show_closed: bool) -> None:
            super().__init__()
            self.items: list[dict] = []
            self.view: list[dict] = []
            self.tag_filter: list[str] = [t for t in (clean_tag(x) for x in (tags or [])) if t]
            self.text_filter = ""
            self.show_closed = show_closed
            self.selected: set[str] = set()
            self.probes: dict[str, str] = {}  # id -> "ok" | "no" | "run"
            self.undo_stack: list[list[tuple[Path, str]]] = []
            self.prompt_mode = ""
            self.col_what = None  # set in on_mount; on_resize can fire first
            self.stamp: tuple[int, int] = (0, 0)  # notebook_stamp() at the last read

        # -- layout ----------------------------------------------------------

        def compose(self) -> ComposeResult:
            yield Static("", id="summary")
            with Vertical():
                yield DataTable(id="items", cursor_type="row", zebra_stripes=True)
                with VerticalScroll(id="detail"):
                    yield Static("", id="detail_body")
            yield Input(placeholder="", id="prompt")
            yield Footer()

        def on_mount(self) -> None:
            table = self.query_one("#items", DataTable)
            table.add_column(" ", key="sel", width=1)
            table.add_column("id", key="id", width=5)
            table.add_column("age", key="age", width=5)
            table.add_column("?", key="probe", width=1)
            # Without a width, the column grows to the longest item and the
            # table scrolls sideways. Pin it to the pane width instead, and
            # cut the text to fit -- see what_width.
            self.col_what = table.add_column("what", key="what", width=40)
            self.reload_items()
            table.focus()
            if POLL_SECONDS > 0:
                self.set_interval(POLL_SECONDS, self.poll_notebook)

        def what_width(self) -> int:
            """Width left for the text column after the fixed columns and padding.

            This reads the app width, not the table width. Inside on_resize,
            layout is not complete, so the table still reports its old size;
            that truncates every row to the 20-column floor.
            """
            fixed = 1 + 5 + 5 + 1  # sel, id, age, probe
            padding = 2 * 5  # DataTable puts one space each side of every cell
            scrollbar = 2
            return max(20, self.size.width - fixed - padding - scrollbar - 1)

        def on_resize(self, _) -> None:
            if self.col_what is None:
                return
            table = self.query_one("#items", DataTable)
            table.columns[self.col_what].width = self.what_width()
            self.fill_table(table.cursor_row)

        # -- data --------------------------------------------------------------

        def reload_items(self, keep_cursor: bool = True) -> None:
            row = self.query_one("#items", DataTable).cursor_row if keep_cursor else 0
            self.stamp = notebook_stamp()
            self.items = load_all()
            self.apply_filters(cursor=row)

        def poll_notebook(self) -> None:
            """Read the notebook again when a note changed on disk.

            Skips while a prompt or modal is open, so it never redraws under
            the user. The cursor follows the item id, not the row number,
            because an added or removed note shifts the rows.
            """
            if self.prompt_mode or isinstance(self.screen, ModalScreen):
                return
            if notebook_stamp() == self.stamp:
                return
            it = self.current()
            self.reload_items()
            if it:
                ids = [i["id"] for i in self.view]
                if it["id"] in ids:
                    self.query_one("#items", DataTable).move_cursor(row=ids.index(it["id"]))

        def apply_filters(self, cursor: int = 0) -> None:
            out = self.items
            if not self.show_closed:
                out = [i for i in out if i["state"] == "open"]
            if self.tag_filter:
                want = set(self.tag_filter)
                out = [i for i in out if want <= set(i["tags"])]
            if self.text_filter:
                needle = self.text_filter.lower()
                out = [
                    i
                    for i in out
                    if needle in f"{i['id']} {i['what']} {i['why']} {i['cmd']}".lower()
                ]
            self.view = out
            self.fill_table(cursor)

        def fill_table(self, cursor: int = 0) -> None:
            table = self.query_one("#items", DataTable)
            table.clear()
            for it in self.view:
                table.add_row(*self.row_cells(it), key=it["id"])
            if self.view:
                table.move_cursor(row=min(cursor, len(self.view) - 1))
            self.update_summary()
            self.update_detail()

        def row_cells(self, it: dict) -> list:
            mark = "*" if it["id"] in self.selected else " "
            age = age_label(it["age_days"])
            stale = it["age_days"] >= STALE_DAYS and it["state"] == "open"
            glyph = {"ok": "+", "no": "-", "run": "~"}.get(self.probes.get(it["id"], ""), " ")
            room = self.what_width()
            what = it["what"] if len(it["what"]) <= room else it["what"][: room - 1] + "…"
            return [
                Text(mark, style="bold cyan"),
                Text(it["id"], style="dim" if it["state"] != "open" else ""),
                Text(age, style="bold red" if stale else "dim"),
                Text(glyph, style={"ok": "green", "no": "red", "run": "yellow"}.get(
                    self.probes.get(it["id"], ""), "")),
                Text(what, style="dim strike" if it["state"] != "open" else ""),
            ]

        def redraw_row(self, item_id: str) -> None:
            it = self.by_id(item_id)
            if not it:
                return
            table = self.query_one("#items", DataTable)
            cells = self.row_cells(it)
            for key, cell in zip(("sel", "id", "age", "probe", "what"), cells):
                try:
                    table.update_cell(item_id, key, cell)
                except KeyError:
                    return

        def by_id(self, item_id: str) -> dict | None:
            return next((i for i in self.view if i["id"] == item_id), None)

        def current(self) -> dict | None:
            table = self.query_one("#items", DataTable)
            if not self.view or table.cursor_row < 0:
                return None
            return self.view[min(table.cursor_row, len(self.view) - 1)]

        def targets(self) -> list[dict]:
            """The selection, or the row under the cursor when nothing is selected."""
            if self.selected:
                return [i for i in self.view if i["id"] in self.selected]
            it = self.current()
            return [it] if it else []

        # -- chrome ------------------------------------------------------------

        def update_summary(self) -> None:
            total_open = sum(1 for i in self.items if i["state"] == "open")
            stale = sum(
                1 for i in self.items if i["state"] == "open" and i["age_days"] >= STALE_DAYS
            )
            bits = [f"{total_open} open", f"{len(self.view)} shown"]
            if stale:
                bits.append(f"[red]{stale} stale[/red]")
            if self.selected:
                bits.append(f"[cyan]{len(self.selected)} selected[/cyan]")
            if self.tag_filter:
                bits.append("tag:" + ",".join(self.tag_filter))
            if self.text_filter:
                bits.append(f"/{self.text_filter}")
            if self.show_closed:
                bits.append("closed too")
            self.query_one("#summary", Static).update("  ·  ".join(bits))

        def update_detail(self) -> None:
            body = self.query_one("#detail_body", Static)
            it = self.current()
            if not it:
                body.update("[dim]nothing to show[/dim]")
                return
            out = [f"[b]{it['id']}[/b]  {it['what']}", ""]
            meta = [f"state: {it['state']}", f"age: {age_label(it['age_days'])}"]
            if it["by"]:
                meta.append(f"by: {it['by']}")
            if it["tags"]:
                meta.append("tags: " + " ".join("#" + t for t in it["tags"]))
            out.append("[dim]" + "   ".join(meta) + "[/dim]")
            if it["why"]:
                out += ["", "[b]Why[/b]", it["why"]]
            if it["cwd"]:
                out += ["", f"[b]In[/b] {it['cwd']}"]
            if it["cmd"]:
                out += ["", "[b]Do this[/b]  [dim](r)[/dim]", f"[green]{it['cmd']}[/green]"]
            if it["verify"]:
                probe_says = {
                    "ok": "  [green](passes -- already done)[/green]",
                    "no": "  [red](fails -- still open)[/red]",
                    "run": "  [yellow](running)[/yellow]",
                }.get(self.probes.get(it["id"], ""), "")
                out += ["", "[b]Done when[/b]  [dim](v)[/dim]" + probe_says, it["verify"]]
            notes = section("\n".join(it["path"].read_text(encoding="utf-8").splitlines()), "Notes")
            if notes:
                out += ["", "[b]Notes[/b]", notes]
            body.update("\n".join(out))

        def on_data_table_row_highlighted(self, _) -> None:
            self.update_detail()

        # -- moving ------------------------------------------------------------

        def action_cursor_down(self) -> None:
            self.query_one("#items", DataTable).action_cursor_down()

        def action_cursor_up(self) -> None:
            self.query_one("#items", DataTable).action_cursor_up()

        def action_top(self) -> None:
            self.query_one("#items", DataTable).move_cursor(row=0)

        def action_bottom(self) -> None:
            if self.view:
                self.query_one("#items", DataTable).move_cursor(row=len(self.view) - 1)

        # -- selecting ---------------------------------------------------------

        def action_select(self) -> None:
            it = self.current()
            if not it:
                return
            self.selected.symmetric_difference_update({it["id"]})
            self.redraw_row(it["id"])
            self.update_summary()
            self.query_one("#items", DataTable).action_cursor_down()

        def action_clear_selection(self) -> None:
            was, self.selected = self.selected, set()
            for item_id in was:
                self.redraw_row(item_id)
            self.update_summary()

        # -- closing -----------------------------------------------------------

        def action_close_done(self) -> None:
            self.close_flow("done")

        def action_close_drop(self) -> None:
            self.close_flow("drop")

        def close_flow(self, verb: str) -> None:
            targets = [i for i in self.targets() if i["state"] == "open"]
            if not targets:
                self.notify("nothing open here", severity="warning")
                return
            if len(targets) == 1:
                self.do_close(targets, verb)
                return
            self.push_screen(
                Confirm(f"{verb} {len(targets)} items?"),
                lambda ok: self.do_close(targets, verb) if ok else None,
            )

        def do_close(self, targets: list[dict], verb: str) -> None:
            batch = [(i["path"], i["path"].read_text(encoding="utf-8")) for i in targets]
            for it in targets:
                close(it, verb)
            self.undo_stack.append(batch)
            reindex()
            self.selected.clear()
            self.reload_items()
            self.notify(f"{len(targets)} {verb}  ·  u undoes it")

        def action_undo(self) -> None:
            if not self.undo_stack:
                self.notify("nothing to undo", severity="warning")
                return
            batch = self.undo_stack.pop()
            for path, text in batch:
                path.write_text(text, encoding="utf-8")
            reindex()
            self.reload_items()
            self.notify(f"{len(batch)} restored")

        # -- probes ------------------------------------------------------------

        def action_verify(self) -> None:
            for it in self.targets():
                self.start_probe(it["id"])

        def action_verify_all(self) -> None:
            todo = [i["id"] for i in self.view if i["state"] == "open" and i["verify"]]
            if not todo:
                self.notify("no probes to run", severity="warning")
                return
            self.notify(f"probing {len(todo)}")
            for item_id in todo:
                self.start_probe(item_id)

        def start_probe(self, item_id: str) -> None:
            it = self.by_id(item_id)
            if not it or not it["verify"] or self.probes.get(item_id) == "run":
                return
            self.probes[item_id] = "run"
            self.redraw_row(item_id)
            self.probe_worker(item_id, dict(it))

        @work(thread=True, group="probe")
        def probe_worker(self, item_id: str, snapshot: dict) -> None:
            ok = probe(snapshot)
            self.call_from_thread(self.probe_done, item_id, ok)

        def probe_done(self, item_id: str, ok: bool) -> None:
            self.probes[item_id] = "ok" if ok else "no"
            self.redraw_row(item_id)
            if self.current() and self.current()["id"] == item_id:
                self.update_detail()

        # -- shelling out ------------------------------------------------------

        def action_run(self) -> None:
            it = self.current()
            if not it:
                return
            if not it["cmd"]:
                self.notify("this item has no command", severity="warning")
                return
            with self.suspend():
                run_cmd_in_terminal(it["cmd"], it["cwd"])
            self.refresh()
            if it["verify"]:
                self.start_probe(it["id"])

        def action_edit(self) -> None:
            it = self.current()
            if not it:
                return
            editor = os.environ.get("EDITOR") or os.environ.get("VISUAL") or "vi"
            with self.suspend():
                subprocess.run([*editor.split(), str(it["path"])])
            reindex()
            self.reload_items()

        def action_yank(self) -> None:
            it = self.current()
            if not it:
                return
            ask_id = it["id"]
            # Both paths on purpose. OSC 52 reaches the clipboard of whichever
            # terminal is attached, including over SSH; pbcopy is what works
            # when the terminal drops OSC 52.
            self.copy_to_clipboard(ask_id)
            if copy_to_system_clipboard(ask_id):
                self.notify(f"yanked {ask_id}")
            else:
                self.notify(f"yanked {ask_id} -- OSC 52 only", severity="warning")

        def action_obsidian(self) -> None:
            it = self.current()
            if not it:
                return
            from urllib.parse import quote

            uri = "obsidian://open?path=" + quote(str(it["path"].resolve()), safe="")
            try:
                subprocess.run(["open", uri], check=False)
                self.notify("handed to Obsidian")
            except OSError as exc:
                self.notify(f"could not open it: {exc}", severity="error")

        # -- the prompt line ---------------------------------------------------

        def open_prompt(self, mode: str, placeholder: str, value: str = "") -> None:
            self.prompt_mode = mode
            prompt = self.query_one("#prompt", Input)
            prompt.placeholder = placeholder
            prompt.value = value
            prompt.add_class("on")
            prompt.focus()
            # The previous filter returns selected. Type to replace it, or
            # press End to keep it and edit.
            if value:
                prompt.select_all()

        def close_prompt(self) -> None:
            self.prompt_mode = ""
            prompt = self.query_one("#prompt", Input)
            prompt.remove_class("on")
            self.query_one("#items", DataTable).focus()

        def action_filter(self) -> None:
            self.open_prompt("text", "filter text -- empty clears it", self.text_filter)

        def action_tag_filter(self) -> None:
            seen: dict[str, int] = {}
            for i in self.items:
                if i["state"] == "open":
                    for t in i["tags"]:
                        seen[t] = seen.get(t, 0) + 1
            top = " ".join(t for t, _ in sorted(seen.items(), key=lambda kv: -kv[1])[:12])
            self.open_prompt("tag", f"tags, space separated -- {top}", " ".join(self.tag_filter))

        def action_note(self) -> None:
            if not self.current():
                return
            self.open_prompt("note", "a line for ## Notes")

        def on_input_submitted(self, event: Input.Submitted) -> None:
            mode, value = self.prompt_mode, event.value.strip()
            self.close_prompt()
            if mode == "text":
                self.text_filter = value
                self.apply_filters()
            elif mode == "tag":
                self.tag_filter = [t for t in (clean_tag(x) for x in value.split()) if t]
                self.apply_filters()
            elif mode == "note" and value:
                it = self.current()
                if it:
                    text = it["path"].read_text(encoding="utf-8").rstrip("\n")
                    if "\n## Notes" not in text:
                        text += "\n\n## Notes\n"
                    it["path"].write_text(f"{text}\n- {now_iso()} -- {value}\n", encoding="utf-8")
                    reindex()
                    self.reload_items()
                    self.notify("noted")

        def on_key(self, event) -> None:
            if self.prompt_mode and event.key == "escape":
                event.stop()
                self.close_prompt()

        # -- the rest ----------------------------------------------------------

        def action_toggle_closed(self) -> None:
            self.show_closed = not self.show_closed
            self.apply_filters()

        def action_clear_filters(self) -> None:
            self.text_filter = ""
            self.tag_filter = []
            self.show_closed = False
            self.apply_filters()

        def action_reload(self) -> None:
            self.reload_items()
            self.notify("read again")

        def action_help(self) -> None:
            self.push_screen(Help())

    return AskApp


def cmd_tui(args: argparse.Namespace) -> int:
    try:
        app_class = build_app_class()
    except ModuleNotFoundError as exc:
        print(f"ask: no TUI ({exc.name} is missing); showing the list", file=sys.stderr)
        return cmd_list(args)
    app_class(getattr(args, "tag", None), bool(getattr(args, "all", False))).run()
    return 0


# --------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="ask", description=__doc__)
    ap.add_argument("--plain", action="store_true", help="tab-separated, no header")
    ap.add_argument("--no-verify", action="store_true", help="skip the probes (fast)")
    ap.add_argument("--no-tui", action="store_true", help="print the list, do not open the TUI")
    sub = ap.add_subparsers(dest="verb")

    def filters(p):
        p.add_argument("--tag", action="append")
        p.add_argument("--cwd")
        p.add_argument("--closed", action="store_true")
        p.add_argument("--all", action="store_true")

    a = sub.add_parser("add")
    a.add_argument("--what", required=True)
    a.add_argument("--why")
    a.add_argument("--cwd")
    a.add_argument("--cmd", action="append")
    a.add_argument("--verify")
    a.add_argument("--tag", action="append")
    a.add_argument("--by")
    a.add_argument("--quiet", action="store_true")
    a.set_defaults(fn=cmd_add)

    for verb in ("done", "drop"):
        p = sub.add_parser(verb)
        p.add_argument("id")
        p.set_defaults(fn=cmd_close, verb=verb)

    p = sub.add_parser("list")
    filters(p)
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("tui")
    filters(p)
    p.set_defaults(fn=cmd_tui)

    p = sub.add_parser("show")
    p.add_argument("id")
    p.set_defaults(fn=cmd_show)

    p = sub.add_parser("note")
    p.add_argument("id")
    p.add_argument("text", nargs="+")
    p.set_defaults(fn=cmd_note)

    p = sub.add_parser("tag")
    p.add_argument("id", nargs="?")
    p.add_argument("tags", nargs="*")
    p.set_defaults(fn=cmd_tag)

    p = sub.add_parser("search")
    p.add_argument("term")
    p.set_defaults(fn=cmd_search)

    sub.add_parser("count").set_defaults(fn=cmd_count)
    sub.add_parser("sweep").set_defaults(fn=cmd_sweep)
    sub.add_parser("log").set_defaults(fn=cmd_log)
    sub.add_parser("db").set_defaults(fn=cmd_db)
    return ap


def main() -> int:
    ap = build_parser()
    args = ap.parse_args()
    # A directory without .zk is almost always a path one level off the real
    # notebook. It reads as zero items, which looks like an empty queue.
    # Refuse instead -- a wrong path must never report "nothing to do".
    if not (NOTEBOOK / ".zk").is_dir():
        print(f"ask: not a zk notebook: {NOTEBOOK}", file=sys.stderr)
        return 2
    if not getattr(args, "fn", None):
        # A terminal gets the TUI. A pipe, a hook, a status line or an agent
        # gets the text list, so no existing caller has to change. --plain and
        # --no-tui say "text" even at a terminal.
        want_tui = (
            sys.stdin.isatty()
            and sys.stdout.isatty()
            and not args.plain
            and not args.no_tui
            and os.environ.get("ASK_NO_TUI", "") not in ("1", "true", "yes")
        )
        args = ap.parse_args(sys.argv[1:] + ["tui" if want_tui else "list"])
    for k in ("tag", "cwd", "closed", "all"):
        if not hasattr(args, k):
            setattr(args, k, None if k in ("tag", "cwd") else False)
    return args.fn(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
