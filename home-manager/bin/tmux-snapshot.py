#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Save the Claude Code session UUID of each tmux pane, to recover after a crash.

This is the tmux port of herdr-snapshot.py. tmux and workmux do not keep the
Claude Code session UUID of each pane. `workmux resurrect` runs
`claude --continue` in each worktree, so it gets the newest session in that
directory, and it restores only one agent per worktree. `claude --resume <uuid>`
needs the exact UUID, and this script saves it.

HOW THE SCRIPT FINDS THE UUID
-----------------------------
    tmux list-panes -a -> pane_pid -> first descendant pid that has
                                      a live session file
                       -> ~/.claude/sessions/<pid>.json -> sessionId

~/.claude/sessions/<pid>.json holds `sessionId` and `cwd` for each live Claude
Code process. It also holds a `tmux` field, "<session>:@<window>.%<pane>". The
script uses that field only when the process tree gives no answer. These files
describe live processes only, so the capture must run while the sessions run.

Each entry says in `source` where its UUID came from:

    "pid"     -- a claude process under the pane had a session file.
    "tmux"    -- the `tmux` field of a live session file named the pane.
    "unknown" -- a claude process runs in the pane, but it has no session file.

The script does not read the workmux agent state in
~/.local/state/workmux/agents/. workmux writes an agent file only when its
agent hooks run, so the directory can be empty while agents run. The session
file is there for every live Claude Code process.

OUTPUT
------
In ~/.local/state/tmux-snapshots (or $TMUX_SNAPSHOT_DIR):

    latest.json            the newest state
    snapshot-<epoch>.json  the history, about 7 days

    {"capturedAt": "<ISO 8601 UTC>",
     "sessions": [{"tmuxSession", "windowIndex", "windowName", "paneIndex",
                   "paneId", "cwd", "sessionId", "source", "pid", "name"}, ...]}

Each file is written to a temporary path and then renamed, so a crash during a
write cannot damage latest.json. The script exits 0 and prints nothing if no
tmux server runs.

If the new capture finds zero Claude Code panes but latest.json has some, the
script keeps the old latest.json and writes nothing. This keeps the last good
state for tmux-restore when tmux restarts.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

# 336 files = 7 days at one snapshot every 30 minutes.
KEEP = 336
TIMEOUT = 20

STATE_DIR = Path(
    os.environ.get("TMUX_SNAPSHOT_DIR")
    or Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    / "tmux-snapshots"
)
LATEST = STATE_DIR / "latest.json"
CLAUDE_SESSION_DIR = Path.home() / ".claude" / "sessions"

PANE_FIELDS = [
    "session_name",
    "window_index",
    "window_name",
    "pane_index",
    "pane_id",
    "pane_pid",
    "pane_current_path",
]


# ---------------------------------------------------------------------------
# tmux and processes


def list_panes() -> list[dict] | None:
    """Give one dict per tmux pane, or None if no tmux server runs."""
    fmt = "\t".join(f"#{{{field}}}" for field in PANE_FIELDS)
    try:
        done = subprocess.run(
            ["tmux", "list-panes", "-a", "-F", fmt],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if done.returncode != 0:
        return None
    panes = []
    for line in done.stdout.splitlines():
        values = line.split("\t")
        if len(values) == len(PANE_FIELDS):
            panes.append(dict(zip(PANE_FIELDS, values)))
    return panes


def process_table() -> tuple[dict[int, list[int]], dict[int, str]]:
    """Give the children of each pid and the command name of each pid."""
    children: dict[int, list[int]] = {}
    names: dict[int, str] = {}
    try:
        done = subprocess.run(
            ["ps", "-A", "-o", "pid=,ppid=,comm="],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return children, names
    for line in done.stdout.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 3:
            continue
        try:
            pid, ppid = int(parts[0]), int(parts[1])
        except ValueError:
            continue
        children.setdefault(ppid, []).append(pid)
        names[pid] = parts[2].strip()
    return children, names


def descendants(root: int, children: dict[int, list[int]]) -> list[int]:
    """Give the pid and all its descendants, nearest first."""
    found, queue = [], [root]
    while queue:
        pid = queue.pop(0)
        found.append(pid)
        queue.extend(children.get(pid, []))
    return found


def is_claude(name: str) -> bool:
    """Tell if a ps command name is the claude binary."""
    return name == "claude" or name.endswith("/claude")


# ---------------------------------------------------------------------------
# Claude Code


def process_is_alive(pid: int) -> bool:
    """Tell if a process with this pid runs now."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def live_claude_sessions() -> dict[int, dict]:
    """Read ~/.claude/sessions/<pid>.json for every live Claude Code process.

    Claude Code does not remove the file when a process dies. This function
    skips dead pids because their data describes sessions that no longer exist.
    """
    sessions: dict[int, dict] = {}
    try:
        files = list(CLAUDE_SESSION_DIR.glob("*.json"))
    except OSError:
        return sessions
    for path in files:
        try:
            pid = int(path.stem)
        except ValueError:
            continue
        if not process_is_alive(pid):
            continue
        try:
            with path.open(encoding="utf-8") as handle:
                record = json.load(handle)
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(record, dict) and record.get("sessionId"):
            sessions[pid] = record
    return sessions


# ---------------------------------------------------------------------------
# The session list


def collect_sessions(panes: list[dict]) -> list[dict]:
    """Build one entry per tmux pane that runs Claude Code."""
    children, names = process_table()
    by_pid = live_claude_sessions()
    by_pane: dict[str, tuple[int, dict]] = {}
    for pid, record in by_pid.items():
        # The field has the form "<session>:@<window>.%<pane>".
        tmux_field = record.get("tmux") or ""
        _, dot, pane_id = tmux_field.rpartition(".")
        if dot and pane_id.startswith("%"):
            by_pane[pane_id] = (pid, record)

    entries: list[dict] = []
    for pane in panes:
        try:
            tree = descendants(int(pane["pane_pid"]), children)
        except ValueError:
            tree = []
        pid = next((p for p in tree if p in by_pid), None)
        source = "pid"
        if pid is None and pane["pane_id"] in by_pane:
            pid, source = by_pane[pane["pane_id"]][0], "tmux"
        if pid is None:
            pid = next((p for p in tree if is_claude(names.get(p, ""))), None)
            if pid is None:
                continue
            source = "unknown"
        record = by_pid.get(pid, {})
        entries.append(
            {
                "tmuxSession": pane["session_name"],
                "windowIndex": int(pane["window_index"]),
                "windowName": pane["window_name"],
                "paneIndex": int(pane["pane_index"]),
                "paneId": pane["pane_id"],
                "cwd": record.get("cwd") or pane["pane_current_path"],
                "sessionId": record.get("sessionId"),
                "source": source,
                "pid": pid,
                "name": record.get("name"),
            }
        )
    return entries


# ---------------------------------------------------------------------------
# Files


def canonical(payload: object) -> str:
    """Give a stable text form of the payload, to compare two captures."""
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))


def previous_sessions() -> list | None:
    """Give the session list of latest.json, or None."""
    try:
        with LATEST.open(encoding="utf-8") as handle:
            return json.load(handle)["sessions"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError):
        return None


def write_atomically(path: Path, document: object) -> None:
    """Write the document to the path with a temporary file and a rename."""
    handle = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    )
    temporary = Path(handle.name)
    try:
        with handle:
            json.dump(document, handle, sort_keys=True, indent=1)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def prune() -> None:
    """Delete the oldest history files and keep the newest KEEP files."""
    try:
        files = sorted(
            STATE_DIR.glob("snapshot-*.json"), key=lambda path: path.stat().st_mtime
        )
    except OSError:
        return
    for old in files[:-KEEP]:
        try:
            old.unlink()
        except OSError:
            pass


# ---------------------------------------------------------------------------


def main() -> int:
    panes = list_panes()
    if panes is None:
        return 0
    sessions = collect_sessions(panes)
    if not sessions and previous_sessions():
        # Zero panes here usually means that tmux is restarting, not that all
        # sessions stopped. Keep the old latest.json for tmux-restore.
        return 0

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    now = time.time()
    document = {
        "capturedAt": datetime.fromtimestamp(now, timezone.utc).isoformat(
            timespec="seconds"
        ),
        "sessions": sessions,
    }
    if canonical(previous_sessions()) != canonical(sessions):
        # Write a history file only when the state changed. An idle weekend
        # must not produce 336 identical files.
        write_atomically(STATE_DIR / f"snapshot-{int(now)}.json", document)
    write_atomically(LATEST, document)
    prune()
    return 0


if __name__ == "__main__":
    sys.exit(main())
