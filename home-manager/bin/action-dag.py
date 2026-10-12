#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6", "markdown-it-py>=3"]
# ///
"""Draw the action graph (DAG) of a multi-step goal, with live status.

A graph is one hand-written YAML file, `<notebook>/<goal>.dag.yaml`. Each node
names a status source: a GitLab MR, an ask-zk item, a read-only `probe:`
command, or a manual value. This script gets the status of every source in
parallel, applies the predecessor rule (see derive()), and writes one
self-contained HTML page (default `<goal>.dag.html`, or the `output:` path).
It also prints a short summary: what is next for the user, the warnings, and
what changed since the last run.

The page is static. Each card is a button that opens a detail panel. The
script puts all panel content in the page when it writes it: the ask notes
(markdown, rendered as HTML), the MR facts and the probe results. Thus the
page works from file:// and as a claude.ai Artifact. A <meta refresh> tag
reloads the page, and the URL hash (location.hash) keeps the selected node, so
an open browser tab stays current.

`<goal>.dag.state.json`, next to the YAML file, keeps the state of each node
from the last run. The next run uses it to mark what changed.

Read-only by design:

  * The script always calls ask-zk with `--no-verify`. Without it,
    `ask-zk list` runs the `--verify` command of each item and closes each
    item whose command passes.
  * `probe:` commands must be read-only. This script runs them with a timeout,
    but it cannot stop a probe that writes. `--check` warns about probes that
    look like they write.
  * The script calls glab with `glab api` GET requests only. It parses the
    output and never prints it, so no token gets to the terminal.
  * Text that goes into the page goes through redact(), which replaces strings
    that look like tokens. Ask notes must never hold a secret; redact() is a
    second protection.
"""

from __future__ import annotations

import argparse
import concurrent.futures as cf
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import yaml
from markdown_it import MarkdownIt

# The Nix wrapper sets ACTION_DAG_NOTEBOOK. ASK_NOTEBOOK points to the same
# notebook (ask-zk keeps its queue there), so the script uses it second.
NOTEBOOK = Path(
    os.environ.get("ACTION_DAG_NOTEBOOK")
    or os.environ.get("ASK_NOTEBOOK")
    or Path.home() / "notes"
)
TEMPLATE = Path(
    os.environ.get("ACTION_DAG_TEMPLATE")
    or Path(__file__).with_name("action-dag.template.html")
)
STALE_DAYS = int(os.environ.get("ASK_STALE_DAYS", "7"))
PROBE_TIMEOUT = 8  # seconds
CALL_TIMEOUT = 30  # seconds, for one glab or ask-zk call
WORKERS = 12
DEFAULT_REFRESH = 60  # seconds between page reloads in the browser

# Node states, in the order the legend shows them.
STATES = ("next", "decide", "wait", "blocked", "done", "unknown")
MANUAL_STATES = ("next", "wait", "decide", "blocked", "done")
SOURCE_KEYS = ("mr", "ask", "probe", "manual")
# A probe that matches this is possibly not read-only. --check gives a warning.
WRITE_HINT = re.compile(
    r"(^|[\s;&|])(rm|mv|cp|tee|touch|mkdir|apply|delete|destroy|create|"
    r"update|patch|put|post|push|commit|done|drop|sed\s+-i)\b"
    r"|>\s*(?!/dev/null|&)",
    re.I,
)
# Strings that look like credentials. redact() replaces each match.
SECRET_PATTERNS = [
    re.compile(r"\b(glpat|gldt|gloas|glptt|glrt|glcbt|glsoat|glimt|glagent|glffct)-[A-Za-z0-9_.\-]{8,}"),
    re.compile(r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"\bxox[abposr]-[A-Za-z0-9\-]{10,}"),
    re.compile(r"\bya29\.[A-Za-z0-9_\-.]{20,}"),
    re.compile(r"(?i)(?P<keep>\bBearer\s+)[A-Za-z0-9+/=_\-.]{20,}"),
    # An upper-case shell variable only (GITLAB_TOKEN=..., API_SECRET=...). Case-
    # sensitive, so a flag such as --secret=<name> (a secret's name) stays.
    re.compile(
        r"(?P<keep>\b[A-Z0-9_]*(?:PRIVATE|SECRET|TOKEN|PASSWORD)[A-Z0-9_]*\s*[=:]\s*['\"]?)"
        r"[A-Za-z0-9+/=_\-.]{16,}"
    ),
]
REDACTED = "[REDACTED]"


class GraphError(Exception):
    """The YAML file cannot be loaded as a graph."""


def redact(text: str) -> str:
    """Replace each string that looks like a token with [REDACTED]."""
    for pat in SECRET_PATTERNS:
        if "keep" in pat.groupindex:  # keep the prefix, replace only the value
            text = pat.sub(lambda m: m.group("keep") + REDACTED, text)
        else:
            text = pat.sub(REDACTED, text)
    return text


# --------------------------------------------------------------------------
# loading


@dataclass
class Node:
    id: str
    title: str
    lane: str | None = None
    sub: str = ""
    link: str = ""
    links: list[dict] = field(default_factory=list)  # [{label, url}], panel buttons
    notes: str = ""  # markdown, shown in the panel
    owner: str = ""
    hold_until: str = ""
    asks: list[str] = field(default_factory=list)
    sources: list[dict] = field(default_factory=list)
    side: bool = False
    tag: str = ""  # short text in the card's id row, for example "runbook 0-3"


@dataclass
class Graph:
    goal: str
    title: str
    summary: str
    lanes: list[dict]
    nodes: dict[str, Node]
    edges: list[tuple[str, str]]
    done: list[dict]
    defaults: dict
    path: Path
    output: Path
    refresh: int


def normalize_sources(raw, defaults: dict) -> list[dict]:
    """Turn the `status:` value into a list of one-key source dicts.

    Accepted forms: a dict with one source key, a list of such dicts, or the
    bare string `next` / `wait` / ... as a short form of `{manual: next}`.
    An `mr:` value can be an int (the iid, with the project and host from
    `defaults`) or a dict.
    """
    if raw is None:
        return [{"manual": "next"}]
    if isinstance(raw, str):
        raw = {"manual": raw}
    if isinstance(raw, dict):
        raw = [raw]
    if not isinstance(raw, list):
        raise GraphError(f"status must be a mapping or a list, not {type(raw).__name__}")
    out = []
    for src in raw:
        if not isinstance(src, dict):
            raise GraphError(f"a status source must be a mapping, not {src!r}")
        keys = [k for k in src if k in SOURCE_KEYS]
        if len(keys) != 1:
            raise GraphError(
                f"a status source needs exactly one of {', '.join(SOURCE_KEYS)}: {src!r}"
            )
        kind = keys[0]
        if kind == "mr":
            mr = src["mr"]
            if isinstance(mr, int):
                mr = {"iid": mr}
            mr = {
                "host": defaults.get("mr_host", "gitlab.com"),
                "project": defaults.get("mr_project", ""),
                **mr,
            }
            if not mr.get("project") or not mr.get("iid"):
                raise GraphError(f"mr needs a project and an iid: {src!r}")
            out.append({"mr": mr})
        elif kind == "ask":
            out.append({"ask": str(src["ask"])})
        elif kind == "probe":
            out.append({"probe": str(src["probe"]), "pending": src.get("pending", "next")})
        else:
            out.append({"manual": str(src["manual"])})
    return out


def mr_url(mr: dict) -> str:
    return f"https://{mr['host']}/{mr['project']}/-/merge_requests/{mr['iid']}"


def link_label(url: str) -> str:
    """A button label for a bare `link:`, guessed from the URL."""
    for part, label in (
        ("/-/merge_requests/", "Open MR"),
        ("/-/jobs/", "Open job"),
        ("/-/pipelines", "Open pipelines"),
        ("/-/blob/", "Open file"),
        ("/-/tree/", "Open directory"),
        ("/-/issues/", "Open issue"),
    ):
        if part in url:
            return label
    return "Open link"


def parse_node(raw: dict, defaults: dict, side: bool) -> Node:
    if not isinstance(raw, dict) or "id" not in raw:
        raise GraphError(f"every node needs an id: {raw!r}")
    nid = str(raw["id"])
    sources = normalize_sources(raw.get("status"), defaults)
    links = []
    for item in raw.get("links") or []:
        if not isinstance(item, dict) or not item.get("url"):
            raise GraphError(f"node {nid}: a links entry is {{label, url}}, not {item!r}")
        links.append({"label": str(item.get("label") or link_label(item["url"])), "url": str(item["url"])})
    link = raw.get("link") or ""
    if not link:
        mrs = [s["mr"] for s in sources if "mr" in s]
        if mrs:
            link = mr_url(mrs[0])
        elif links:
            link = links[0]["url"]
    asks = raw.get("asks") or []
    if isinstance(asks, str):
        asks = [asks]
    return Node(
        id=nid,
        title=str(raw.get("title", nid)),
        lane=raw.get("lane"),
        sub=str(raw.get("sub", "")),
        link=link,
        links=links,
        notes=str(raw.get("notes", "") or ""),
        owner=str(raw.get("owner", "")),
        hold_until=str(raw.get("hold_until", "") or ""),
        asks=[str(a) for a in asks],
        sources=sources,
        side=side,
        tag=str(raw.get("tag", "")),
    )


def load_graph(path: Path) -> Graph:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        raise GraphError(f"{path}: not valid YAML: {e}") from e
    return graph_from_dict(data or {}, path)


def graph_from_dict(data: dict, path: Path) -> Graph:
    defaults = data.get("defaults") or {}
    nodes: dict[str, Node] = {}
    for side, key in ((False, "nodes"), (True, "side")):
        for raw in data.get(key) or []:
            n = parse_node(raw, defaults, side)
            if n.id in nodes:
                raise GraphError(f"node id {n.id!r} is used twice")
            nodes[n.id] = n
    edges = []
    for e in data.get("edges") or []:
        if not (isinstance(e, (list, tuple)) and len(e) == 2):
            raise GraphError(f"an edge is a pair [from, to], not {e!r}")
        edges.append((str(e[0]), str(e[1])))
    lanes = data.get("lanes") or []
    lanes = [ln if isinstance(ln, dict) else {"id": str(ln), "title": str(ln)} for ln in lanes]
    goal = str(data.get("goal") or path.name.removesuffix(".dag.yaml"))
    # `output:` is relative to the directory of the YAML file (the notebook).
    output = path.parent / str(data.get("output") or f"{goal}.dag.html")
    refresh = data.get("refresh_seconds", DEFAULT_REFRESH)
    try:
        refresh = max(0, int(refresh))
    except (TypeError, ValueError) as e:
        raise GraphError(f"refresh_seconds must be a whole number, not {refresh!r}") from e
    return Graph(
        goal=goal,
        title=str(data.get("title") or goal),
        summary=str(data.get("summary", "")),
        lanes=lanes,
        nodes=nodes,
        edges=edges,
        done=data.get("done") or [],
        defaults=defaults,
        path=path,
        output=output,
        refresh=refresh,
    )


# --------------------------------------------------------------------------
# validation


def find_cycle(nodes: list[str], edges: list[tuple[str, str]]) -> list[str] | None:
    """Return one cycle as a list of ids (first id repeated at the end), or None."""
    succ: dict[str, list[str]] = {n: [] for n in nodes}
    for a, b in edges:
        succ.setdefault(a, []).append(b)
        succ.setdefault(b, [])
    WHITE, GREY, BLACK = 0, 1, 2
    color = {n: WHITE for n in succ}
    stack: list[str] = []

    def visit(n: str) -> list[str] | None:
        color[n] = GREY
        stack.append(n)
        for m in succ[n]:
            if color[m] == GREY:
                return stack[stack.index(m):] + [m]
            if color[m] == WHITE:
                found = visit(m)
                if found:
                    return found
        stack.pop()
        color[n] = BLACK
        return None

    for n in succ:
        if color[n] == WHITE:
            found = visit(n)
            if found:
                return found
    return None


def check_graph(g: Graph) -> tuple[list[str], list[str]]:
    """Return (errors, warnings). An error stops the run (exit 2, or exit 1
    with --check). A warning does not stop the run."""
    errors: list[str] = []
    warnings: list[str] = []
    ids = set(g.nodes)
    lane_ids = [ln.get("id") for ln in g.lanes]
    if not g.lanes:
        errors.append("no lanes: add a `lanes:` list")
    if len(set(lane_ids)) != len(lane_ids):
        errors.append("a lane id is used twice")
    if g.output.resolve() == g.path.resolve() or g.output.suffix != ".html":
        errors.append(f"output must be an .html file other than the YAML file: {g.output.name}")
    for a, b in g.edges:
        for x in (a, b):
            if x not in ids:
                errors.append(f"edge [{a}, {b}]: unknown node id {x!r}")
        if a == b:
            errors.append(f"edge [{a}, {b}]: a node cannot depend on itself")
    cycle = find_cycle(list(ids), [(a, b) for a, b in g.edges if a in ids and b in ids])
    if cycle:
        errors.append("cycle: " + " -> ".join(cycle))
    for n in g.nodes.values():
        if not n.side and n.lane not in lane_ids:
            errors.append(f"node {n.id}: lane {n.lane!r} is not in `lanes`")
        if not n.link and not n.links:
            warnings.append(f"node {n.id}: no link")
        for url in [n.link] + [x["url"] for x in n.links]:
            if url and not url.startswith("https://"):
                warnings.append(f"node {n.id}: link is not a full https:// URL: {url}")
        if n.hold_until and n.hold_until not in ids:
            errors.append(f"node {n.id}: hold_until {n.hold_until!r} is not a node id")
        for s in n.sources:
            if "manual" in s and s["manual"] not in MANUAL_STATES:
                errors.append(
                    f"node {n.id}: manual {s['manual']!r} is not one of {', '.join(MANUAL_STATES)}"
                )
            if "probe" in s:
                if s["pending"] not in MANUAL_STATES:
                    errors.append(
                        f"node {n.id}: pending {s['pending']!r} is not one of {', '.join(MANUAL_STATES)}"
                    )
                if WRITE_HINT.search(s["probe"]):
                    warnings.append(
                        f"node {n.id}: the probe possibly writes. Probes must be read-only: {s['probe']}"
                    )
        if n.hold_until and not any("mr" in s for s in n.sources):
            warnings.append(f"node {n.id}: hold_until has an effect only on an mr source")
    for d in g.done:
        if not isinstance(d, dict) or not d.get("label"):
            errors.append(f"done entry needs a label: {d!r}")
        elif not str(d.get("link", "")).startswith("https://"):
            warnings.append(f"done entry {d['label']!r}: no https:// link")
    return errors, warnings


# --------------------------------------------------------------------------
# status sources


@dataclass
class Result:
    """What the sources say about one node."""

    state: str  # one of STATES
    pill: str = ""  # short label for the card, for example "Draft"
    detail: str = ""  # one line for the tooltip and the summary
    warn: list[str] = field(default_factory=list)
    mr: dict | None = None  # MR facts, for hold_until
    facts: list[dict] = field(default_factory=list)  # one per source, for the panel


def run(cmd: list[str], timeout: int = CALL_TIMEOUT) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL
    )


def short_err(text: str) -> str:
    text = " ".join((text or "").split())
    return redact(text[:240]) or "no error text"


def tail(text: str, lines: int = 6) -> str:
    return redact("\n".join((text or "").strip().splitlines()[-lines:]))


class Sources:
    """The real status sources. Tests replace the five `fetch_*` methods."""

    def ask_zk_cmd(self) -> list[str]:
        exe = shutil.which("ask-zk") or str(Path.home() / ".claude/bin/ask-zk")
        # --no-verify is mandatory: without it, `list` runs the --verify
        # command of each item and closes items. --plain gives tab-separated rows.
        return [exe, "--plain", "--no-verify"]

    def fetch_mr(self, mr: dict) -> dict:
        proj = urllib.parse.quote(mr["project"], safe="")
        base = f"projects/{proj}/merge_requests/{mr['iid']}"
        p = run(["glab", "api", "--hostname", mr["host"], base])
        if p.returncode != 0:
            raise RuntimeError(f"glab api {base}: {short_err(p.stderr)}")
        data = json.loads(p.stdout)
        a = run(["glab", "api", "--hostname", mr["host"], f"{base}/approvals"])
        if a.returncode == 0:
            ap = json.loads(a.stdout)
            data["_approved"] = bool(ap.get("approved")) and bool(ap.get("approved_by"))
            data["_approved_by"] = [x["user"]["username"] for x in ap.get("approved_by", [])]
            data["_approvals_left"] = ap.get("approvals_left")
        return data

    def fetch_asks(self) -> dict[str, dict]:
        """All asks, open and closed: {id: {state, age_days, what}}."""
        p = run(self.ask_zk_cmd() + ["list", "--all"])
        if p.returncode not in (0, 3):
            raise RuntimeError(f"ask-zk list: {short_err(p.stderr)}")
        out = {}
        for line in p.stdout.splitlines():
            parts = line.split("\t")
            if len(parts) < 4:
                continue
            iid, age, state, what = parts[0], parts[1], parts[2], parts[3]
            m = re.match(r"(\d+)d", age)
            out[iid] = {"state": state, "age_days": int(m.group(1)) if m else 0, "what": what}
        return out

    def fetch_ask_show(self, iid: str) -> dict:
        """Fallback for a legacy ask id that `list` does not print."""
        p = run(self.ask_zk_cmd() + ["show", iid])
        if p.returncode != 0:
            raise RuntimeError(f"ask-zk show {iid}: {short_err(p.stderr or p.stdout)}")
        state = "open"
        for line in p.stdout.splitlines():
            if line.startswith("closed: "):
                state = line.split(":", 1)[1].strip()
                break
            if re.match(r"^- \[x\] ", line, re.I):
                state = "done"
                break
            if line.startswith("- [ ] "):
                break
        return {"state": state, "age_days": 0, "what": "", "text": p.stdout}

    def fetch_ask_note(self, iid: str) -> tuple[str, str] | None:
        """(path, markdown) of the ask note, or None. Reads the file only."""
        path = NOTEBOOK / f"{iid}.md"
        try:
            return str(path), path.read_text(encoding="utf-8")
        except OSError:
            return None

    def fetch_probe(self, cmd: str) -> dict:
        """{rc, stderr} of the probe. Raises TimeoutError after PROBE_TIMEOUT."""
        try:
            p = subprocess.run(
                ["/bin/sh", "-c", cmd],
                capture_output=True,
                text=True,
                timeout=PROBE_TIMEOUT,
                stdin=subprocess.DEVNULL,
            )
        except subprocess.TimeoutExpired as e:
            raise TimeoutError(f"probe timed out after {PROBE_TIMEOUT} s") from e
        return {"rc": p.returncode, "stderr": tail(p.stderr)}


def mr_result(mr: dict, data: dict) -> Result:
    state = data.get("state")
    pipeline = data.get("head_pipeline") or {}
    pipe = pipeline.get("status") or "none"
    ref = f"!{mr['iid']}"
    approved = data.get("_approved")
    merge_status = data.get("detailed_merge_status") or ""
    facts = {
        "kind": "mr",
        "ref": ref,
        "url": data.get("web_url") or mr_url(mr),
        "title": redact(str(data.get("title") or "")),
        "state": state,
        "draft": bool(data.get("draft")),
        "approved": bool(approved),
        "approved_by": data.get("_approved_by") or [],
        "approvals_left": data.get("_approvals_left"),
        "pipeline": pipe,
        "pipeline_url": pipeline.get("web_url") or "",
        "merge_status": merge_status,
    }
    r: Result
    if state == "merged":
        r = Result("done", "Merged", f"{ref} merged")
    elif state == "closed":
        r = Result(
            "unknown", "Closed", f"{ref} is closed, not merged",
            warn=[f"{ref} is closed without a merge. Update the graph."],
        )
    else:
        detail = f"{ref} open, pipeline {pipe}"
        if data.get("draft"):
            r = Result("wait", "Draft", f"{detail}, draft")
        elif pipe in ("failed", "canceled"):
            r = Result("next", "CI " + pipe, f"{detail}: fix CI")
        elif approved or merge_status == "mergeable":
            by = ", ".join(data.get("_approved_by") or [])
            r = Result("next", "Merge", f"{detail}, approved{' by ' + by if by else ''}")
        else:
            r = Result("wait", "Review", f"{detail}, needs approval")
    r.mr = facts
    r.facts = [facts]
    return r


def ask_result(iid: str, item: dict | None) -> Result:
    if item is None:
        return Result("unknown", "?", f"ask {iid} not found", warn=[f"ask {iid} not found"])
    st = item["state"]
    if st == "done":
        return Result("done", "Done", f"ask {iid} closed")
    if st == "drop":
        return Result(
            "unknown", "Dropped", f"ask {iid} was dropped",
            warn=[f"ask {iid} was dropped. Update the graph."],
        )
    warn = []
    if item.get("age_days", 0) >= STALE_DAYS:
        warn.append(f"ask {iid} is stale: open for {item['age_days']} days")
    return Result("next", "Next", f"ask {iid} open", warn=warn)


def combine(results: list[Result]) -> Result:
    """Merge the results of the sources of one node. The node is done when one
    source is done. If no source is done, the first source sets the state."""
    facts = [f for r in results for f in r.facts]
    mr = next((r.mr for r in results if r.mr), None)
    for r in results:
        if r.state == "done":
            # An ask that is still open on a done node is a box to tick.
            others = [
                f"{x.detail}, but {r.detail}: tick the ask"
                for x in results
                if x is not r and x.detail.startswith("ask ") and x.state == "next"
            ]
            return Result("done", r.pill, r.detail, warn=others, mr=mr, facts=facts)
    first = results[0]
    warn = [w for r in results for w in r.warn]
    return Result(first.state, first.pill, first.detail, warn=warn, mr=mr, facts=facts)


def ask_facts(iid: str, item: dict | None, note: tuple[str, str] | None, related: bool) -> dict:
    f = {"kind": "ask", "id": iid, "related": related, "path": "", "md": ""}
    if item:
        f.update(state=item["state"], age_days=item.get("age_days", 0))
    else:
        f.update(state="not found", age_days=None)
    if note:
        f["path"], f["md"] = note[0], note[1]
    elif item and item.get("text"):
        f["md"] = item["text"]
    return f


def resolve_sources(g: Graph, src: Sources) -> dict[str, Result]:
    """Get the status that the sources of each node give, in parallel.
    A failed lookup gives `unknown`; this function never raises."""
    nodes = list(g.nodes.values())
    all_asks = {s["ask"] for n in nodes for s in n.sources if "ask" in s} | {
        a for n in nodes for a in n.asks
    }
    asks: dict[str, dict] = {}
    asks_err = ""
    jobs: dict[cf.Future, tuple[str, int]] = {}
    with cf.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        ask_future = pool.submit(src.fetch_asks) if all_asks else None
        note_futures = {a: pool.submit(src.fetch_ask_note, a) for a in all_asks}
        for n in nodes:
            for i, s in enumerate(n.sources):
                if "mr" in s:
                    jobs[pool.submit(src.fetch_mr, s["mr"])] = (n.id, i)
                elif "probe" in s:
                    jobs[pool.submit(src.fetch_probe, s["probe"])] = (n.id, i)
        if ask_future:
            try:
                asks = ask_future.result()
            except Exception as e:  # noqa: BLE001 -- show it, do not crash
                asks_err = str(e)
        # Asks that `list` did not print: try `show` (a legacy ask id).
        if not asks_err:
            missing = all_asks - set(asks)
            for iid, fut in {i: pool.submit(src.fetch_ask_show, i) for i in missing}.items():
                try:
                    asks[iid] = fut.result()
                except Exception:  # noqa: BLE001
                    pass
        notes: dict[str, tuple[str, str] | None] = {}
        for iid, fut in note_futures.items():
            try:
                notes[iid] = fut.result()
            except Exception:  # noqa: BLE001
                notes[iid] = None
        raw: dict[tuple[str, int], object] = {}
        for fut, key in jobs.items():
            try:
                raw[key] = fut.result()
            except Exception as e:  # noqa: BLE001
                raw[key] = e

    out: dict[str, Result] = {}
    for n in nodes:
        results = []
        for i, s in enumerate(n.sources):
            if "manual" in s:
                who = f", owner {n.owner}" if n.owner and n.owner != "me" else ""
                r = Result(s["manual"], "", f"set by hand{who}")
                r.facts = [{"kind": "manual", "state": s["manual"]}]
            elif "ask" in s:
                if asks_err:
                    r = Result("unknown", "?", asks_err)
                else:
                    r = ask_result(s["ask"], asks.get(s["ask"]))
                r.facts = [ask_facts(s["ask"], asks.get(s["ask"]), notes.get(s["ask"]), False)]
            else:
                got = raw.get((n.id, i))
                if isinstance(got, Exception):
                    r = Result("unknown", "?", short_err(str(got)))
                    kind = "mr" if "mr" in s else "probe"
                    f = {"kind": kind, "error": short_err(str(got))}
                    if kind == "mr":
                        f.update(ref=f"!{s['mr']['iid']}", url=mr_url(s["mr"]))
                    else:
                        f.update(cmd=s["probe"])
                    r.facts = [f]
                elif "mr" in s:
                    r = mr_result(s["mr"], got)
                else:
                    if isinstance(got, int):  # tolerate a bare exit code
                        got = {"rc": got, "stderr": ""}
                    rc = got["rc"]
                    if rc == 0:
                        r = Result("done", "Done", "probe passed")
                    else:
                        r = Result(s["pending"], "", f"probe exit {rc}")
                    r.facts = [{"kind": "probe", "cmd": s["probe"], "rc": rc, "stderr": got.get("stderr", "")}]
            results.append(r)
        res = combine(results)
        # Asks named in `asks:` add only stale and dropped warnings. They never
        # set the state.
        for a in n.asks:
            if not asks_err:
                res.warn.extend(
                    w for w in ask_result(a, asks.get(a)).warn if "stale" in w or "dropped" in w
                )
            res.facts.append(ask_facts(a, asks.get(a), notes.get(a), True))
        out[n.id] = res
    return out


# --------------------------------------------------------------------------
# derivation


PILL = {
    "next": "Next",
    "wait": "Waiting",
    "decide": "Decide",
    "blocked": "Blocked",
    "done": "Done",
    "unknown": "Unknown",
}


@dataclass
class Derived:
    state: str
    pill: str
    detail: str
    warn: list[str]
    own: str  # the state the sources gave, before the predecessors
    facts: list[dict] = field(default_factory=list)


def predecessors(g: Graph) -> dict[str, list[str]]:
    preds: dict[str, list[str]] = {n: [] for n in g.nodes}
    for a, b in g.edges:
        if b in preds and a in g.nodes:
            preds[b].append(a)
    return preds


def successors(g: Graph) -> dict[str, list[str]]:
    succ: dict[str, list[str]] = {n: [] for n in g.nodes}
    for a, b in g.edges:
        if a in succ and b in g.nodes:
            succ[a].append(b)
    return succ


def derive(g: Graph, own: dict[str, Result]) -> dict[str, Derived]:
    """Apply the predecessor rule.

    * A node that is done stays done.
    * A node with a predecessor that is not done is blocked.
    * Otherwise the node keeps the state its own source gives.

    Also adds the hold_until warnings.
    """
    preds = predecessors(g)
    out: dict[str, Derived] = {}
    for nid, node in g.nodes.items():
        r = own[nid]
        warn = list(r.warn)
        open_preds = [p for p in preds[nid] if own[p].state != "done"]
        if r.state == "done":
            state, pill = "done", r.pill or PILL["done"]
        elif open_preds:
            state, pill = "blocked", PILL["blocked"]
        else:
            state = r.state
            pill = r.pill or PILL[state]
            if state == "wait" and node.owner and node.owner not in ("me", "reviewer") and not r.pill:
                pill = node.owner
        if node.hold_until and r.mr and "state" in r.mr:
            hold = own.get(node.hold_until)
            if hold and hold.state != "done":
                ref = r.mr.get("ref", "the MR")
                if r.mr["state"] == "merged":
                    warn.append(f"{ref} merged before {node.hold_until} was done")
                elif r.mr["state"] == "opened" and (not r.mr["draft"] or r.mr["approved"]):
                    how = "approved" if r.mr["approved"] else "out of draft"
                    warn.append(f"{ref} is {how}. Do not merge before {node.hold_until}.")
        detail = r.detail
        if state == "blocked":
            detail = f"waits for {', '.join(open_preds)}; {r.detail}"
        out[nid] = Derived(state, pill, detail, warn, r.state, r.facts)
    return out


# --------------------------------------------------------------------------
# files


def write_atomic(path: Path, text: str) -> None:
    """Write to a temporary file in the same directory, then rename it. Thus a
    browser that reloads the page never reads a half-written file."""
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def state_path(g: Graph) -> Path:
    return g.path.with_name(f"{g.goal}.dag.state.json")


def load_last(g: Graph) -> dict:
    try:
        return json.loads(state_path(g).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def changes(last: dict, derived: dict[str, Derived]) -> dict[str, str]:
    """{node id: previous state} for each node whose state changed."""
    prev = last.get("nodes", {})
    return {
        nid: prev[nid]["state"]
        for nid, d in derived.items()
        if nid in prev and prev[nid].get("state") != d.state
    }


def save_state(g: Graph, derived: dict[str, Derived], when: str) -> None:
    data = {
        "generated": when,
        "nodes": {nid: {"state": d.state, "detail": d.detail} for nid, d in derived.items()},
    }
    write_atomic(state_path(g), json.dumps(data, indent=2, sort_keys=True) + "\n")


# --------------------------------------------------------------------------
# markdown


_MD = MarkdownIt("commonmark", {"html": False, "linkify": False}).enable("table")
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.S)
PRE = re.compile(r"<pre><code(?: class=\"language-([\w+-]+)\")?>")


def split_frontmatter(text: str) -> tuple[dict, str]:
    m = FRONTMATTER.match(text)
    if not m:
        return {}, text
    try:
        meta = yaml.load(m.group(1), Loader=yaml.BaseLoader) or {}  # keep every value a string
    except yaml.YAMLError:
        meta = {}
    return (meta if isinstance(meta, dict) else {}), text[m.end():]


def md_to_html(text: str) -> str:
    """Convert markdown to safe HTML. First redact the tokens. Escape raw HTML
    in the source (html=False). Add a Copy button to each code block."""
    out = _MD.render(redact(text))

    def wrap(m: re.Match) -> str:
        lang = f'<span class="lang">{esc(m.group(1))}</span>' if m.group(1) else ""
        return (
            f'<div class="code">{lang}<button type="button" class="copy">Copy</button>'
            f"{m.group(0)}"
        )

    out = PRE.sub(wrap, out)
    return out.replace("</code></pre>", "</code></pre></div>")


# --------------------------------------------------------------------------
# rendering


def esc(s) -> str:
    return html.escape(str(s), quote=True)


def id_row(node: Node) -> str:
    bits = [node.id]
    if node.tag:
        bits.append(node.tag)
    for s in node.sources:
        if "mr" in s:
            bits.append(f"!{s['mr']['iid']}")
        elif "ask" in s:
            bits.append(f"ask {s['ask']}")
    if node.asks:
        bits.append(("ask " if len(node.asks) == 1 else "asks ") + ", ".join(node.asks))
    return " · ".join(bits)


def card(node: Node, d: Derived, prev: str | None) -> str:
    tip = d.detail + ("; " + "; ".join(d.warn) if d.warn else "")
    sub = f'<span class="sub">{esc(node.sub)}</span>' if node.sub else ""
    warn = "".join(f'<span class="warn">{esc(w)}</span>' for w in d.warn)
    changed = (
        f'<span class="chg" title="Changed since the last run">was {esc(prev)}</span>'
        if prev
        else ""
    )
    return (
        f'<button type="button" class="node s-{d.state}" id="n-{esc(node.id)}" '
        f'data-node="{esc(node.id)}" aria-controls="panel" aria-expanded="false" '
        f'title="{esc(tip)}">'
        f'<span class="top"><span class="id">{esc(id_row(node))}</span>'
        f'<span class="pills">{changed}<span class="pill">{esc(d.pill)}</span></span></span>'
        f'<span class="title">{esc(node.title)}</span>{sub}{warn}</button>'
    )


def button(label: str, url: str) -> str:
    return (
        f'<a class="btn" href="{esc(url)}" target="_blank" rel="noopener">{esc(label)}</a>'
        if url.startswith("https://")
        else ""
    )


def chips(ids: list[str], derived: dict[str, Derived], g: Graph) -> str:
    if not ids:
        return '<span class="none">nothing</span>'
    return "".join(
        f'<button type="button" class="chip s-{derived[i].state}" data-goto="{esc(i)}" '
        f'title="{esc(g.nodes[i].title)} ({esc(derived[i].state)})">{esc(i)}</button>'
        for i in ids
    )


def fact_html(f: dict) -> str:
    kind = f["kind"]
    if kind == "mr":
        if f.get("error"):
            return (
                f'<section><h4>Merge request {esc(f["ref"])}</h4>'
                f'<p class="err">Lookup failed: {esc(f["error"])}</p></section>'
            )
        approvals = (
            "approved by " + ", ".join(f["approved_by"]) if f["approved_by"]
            else "not approved"
        )
        if f.get("approvals_left"):
            approvals += f", {f['approvals_left']} approval(s) left"
        rows = [
            ("Title", esc(f["title"])),
            ("State", esc(f["state"]) + (" (draft)" if f["draft"] else "")),
            ("Approvals", esc(approvals)),
            ("Pipeline", esc(f["pipeline"])),
        ]
        if f.get("merge_status"):
            rows.append(("Merge status", esc(f["merge_status"])))
        btns = button("Open MR", f["url"]) + button("Open pipeline", f.get("pipeline_url", ""))
        return (
            f'<section><h4>Merge request {esc(f["ref"])}</h4>{dl(rows)}'
            f'<div class="btns">{btns}</div></section>'
        )
    if kind == "probe":
        cmd = (
            '<div class="code"><span class="lang">sh</span>'
            '<button type="button" class="copy">Copy</button>'
            f"<pre><code>{esc(redact(f['cmd']))}</code></pre></div>"
        )
        if f.get("error"):
            result = f'<p class="err">{esc(f["error"])}</p>'
        else:
            ok = "passed (exit 0)" if f["rc"] == 0 else f"not done yet (exit {f['rc']})"
            result = f"<p>Last result: {esc(ok)}</p>"
            if f["rc"] != 0 and f.get("stderr"):
                result += f'<pre class="stderr"><code>{esc(f["stderr"])}</code></pre>'
        return f"<section><h4>Probe (read-only)</h4>{cmd}{result}</section>"
    if kind == "ask":
        meta, body = split_frontmatter(f.get("md") or "")
        rows = [
            ("State", esc(f.get("state", "?"))),
            ("Age", esc(f"{f['age_days']} days") if f.get("age_days") is not None else "?"),
        ]
        if meta.get("created"):
            rows.append(("Created", esc(meta["created"])))
        if meta.get("closed"):
            rows.append(("Closed", esc(f"{meta['closed']} {meta.get('closed_ts', '')}".strip())))
        if f.get("path"):
            rows.append(("Note", f"<code>{esc(f['path'])}</code>"))
        note = (
            f'<div class="md">{md_to_html(body)}</div>' if body.strip()
            else '<p class="err">The note file was not found.</p>'
        )
        title = f"Related ask {esc(f['id'])}" if f["related"] else f"Ask {esc(f['id'])}"
        if f["related"]:
            return f"<section><details><summary><h4>{title}</h4></summary>{dl(rows)}{note}</details></section>"
        return f"<section><h4>{title}</h4>{dl(rows)}{note}</section>"
    return f'<section><h4>Set by hand</h4><p>State: {esc(f["state"])}</p></section>'


def dl(rows: list[tuple[str, str]]) -> str:
    return "<dl>" + "".join(f"<dt>{k}</dt><dd>{v}</dd>" for k, v in rows) + "</dl>"


def panel(node: Node, d: Derived, g: Graph, derived, preds, succs, prev: str | None) -> str:
    """The detail panel of one node, as HTML. The page keeps it in a <template>."""
    links = list(node.links)
    known = {x["url"] for x in links}
    mr_urls = {f.get("url") for f in d.facts if f["kind"] == "mr"}
    if node.link and node.link not in known and node.link not in mr_urls:
        links.insert(0, {"label": link_label(node.link), "url": node.link})
    btns = "".join(button(x["label"], x["url"]) for x in links)
    warn = "".join(f'<p class="warn">{esc(w)}</p>' for w in d.warn)
    changed = f'<p class="chgline">Changed since the last run: was {esc(prev)}</p>' if prev else ""
    notes = f'<section><h4>Notes</h4><div class="md">{md_to_html(node.notes)}</div></section>' if node.notes else ""
    owner = f" · owner {esc(node.owner)}" if node.owner else ""
    return (
        f'<template id="p-{esc(node.id)}">'
        f'<p class="id">{esc(id_row(node))}{owner}</p>'
        f'<h3 tabindex="-1">{esc(node.title)}</h3>'
        f'<p class="state s-{d.state}"><span class="pill">{esc(d.pill)}</span> {esc(d.detail)}</p>'
        f"{changed}{warn}"
        + (f'<p class="sub">{esc(node.sub)}</p>' if node.sub else "")
        + (f'<div class="btns">{btns}</div>' if btns else "")
        + '<div class="rel"><span>Waits on</span>'
        + f"<div>{chips(preds[node.id], derived, g)}</div>"
        + "<span>Unblocks</span>"
        + f"<div>{chips(succs[node.id], derived, g)}</div></div>"
        + notes
        + "".join(fact_html(f) for f in d.facts)
        + "</template>"
    )


def render(g: Graph, derived: dict[str, Derived], changed: dict[str, str], when: str, template: str) -> str:
    lanes_html = []
    for ln in g.lanes:
        cards = [
            card(n, derived[n.id], changed.get(n.id))
            for n in g.nodes.values()
            if not n.side and n.lane == ln["id"]
        ]
        sub = f"<small>{esc(ln['sub'])}</small>" if ln.get("sub") else ""
        center = ln.get("align") == "center"
        spacer = '<div class="spacer"></div>' if center else ""
        lanes_html.append(
            f'<section class="lane"><h2>{esc(ln.get("title", ln["id"]))}{sub}</h2>'
            f"{spacer}{''.join(cards)}{spacer}</section>"
        )
    done_html = ""
    if g.done:
        items = "".join(
            f'<a href="{esc(d.get("link", "#"))}" target="_blank" rel="noopener">{esc(d["label"])}</a>'
            for d in g.done
        )
        done_html = f'<div class="doneline"><span>Done:</span>{items}</div>'
    side_nodes = [n for n in g.nodes.values() if n.side]
    side_html = ""
    if side_nodes:
        side_html = (
            '<div class="side"><h3>Side tracks, not on the path</h3>'
            + "".join(card(n, derived[n.id], changed.get(n.id)) for n in side_nodes)
            + "</div>"
        )
    preds, succs = predecessors(g), successors(g)
    panels = "\n".join(
        panel(n, derived[n.id], g, derived, preds, succs, changed.get(n.id)) for n in g.nodes.values()
    )
    edges = [[f"n-{a}", f"n-{b}"] for a, b in g.edges]
    counts = {s: sum(1 for d in derived.values() if d.state == s) for s in STATES}
    count_txt = " · ".join(f"{counts[s]} {s}" for s in STATES if counts[s])
    refresh = (
        f'<meta http-equiv="refresh" content="{g.refresh}">' if g.refresh else ""
    )
    reload_txt = f" · reloads every {g.refresh} s" if g.refresh else ""
    repl = {
        "{{REFRESH}}": refresh,
        "{{TITLE}}": esc(g.title),
        "{{SUMMARY}}": esc(g.summary),
        "{{GENERATED}}": esc(when),
        "{{META}}": esc(
            f"from {g.path.name}{reload_txt} · {count_txt} · "
            'arrows mean "must finish before" · select a card for its details'
        ),
        "{{COLUMNS}}": str(max(1, len(g.lanes))),
        "{{LANES}}": "\n".join(lanes_html),
        "{{DONE}}": done_html,
        "{{SIDE}}": side_html,
        "{{PANELS}}": panels,
        "{{STORAGE_KEY}}": esc(f"action-dag:{g.goal}"),
        # json.dumps output sits in a <script>: escape "</" so it cannot close it.
        "{{EDGES_JSON}}": json.dumps(edges).replace("</", "<\\/"),
    }
    # One pass, so a "{{...}}" inside inserted text is never replaced again.
    out = re.sub(r"\{\{[A-Z_]+\}\}", lambda m: repl.get(m.group(0), m.group(0)), template)
    return redact(out)


# --------------------------------------------------------------------------
# terminal summary


def summary(
    g: Graph, derived: dict[str, Derived], changed: dict[str, str], first_run: bool = False
) -> str:
    lines = [f"{g.title} ({g.goal})"]
    mine = [
        n
        for n in g.nodes.values()
        if derived[n.id].state in ("next", "decide") and n.owner in ("", "me")
    ]
    lines.append("")
    lines.append("Next for you:" if mine else "Next for you: nothing")
    for n in mine:
        d = derived[n.id]
        ask_ids = [s["ask"] for s in n.sources if "ask" in s] + n.asks
        ask_txt = f"  (ask {', '.join(ask_ids)})" if ask_ids else ""
        lines.append(f"  [{d.state}] {n.id}  {n.title}{ask_txt}")
        if n.link:
            lines.append(f"         {n.link}")
    warns = [(n, w) for n in g.nodes.values() for w in derived[n.id].warn]
    unknown = [n for n in g.nodes.values() if derived[n.id].state == "unknown"]
    if warns or unknown:
        lines.append("")
        lines.append("WARNINGS:")
        for n, w in warns:
            lines.append(f"  !! {n.id}: {w}")
            if n.link:
                lines.append(f"         {n.link}")
        for n in unknown:
            lines.append(f"  ?? {n.id}: status unknown: {derived[n.id].detail}")
    lines.append("")
    if changed:
        lines.append("Changed since the last run:")
        for nid, prev in changed.items():
            lines.append(f"  {nid}: {prev} -> {derived[nid].state}  {g.nodes[nid].title}")
    elif first_run:
        lines.append(f"Changed since the last run: first run, no {state_path(g).name} yet")
    else:
        lines.append("Changed since the last run: nothing")
    waiting = [n for n in g.nodes.values() if derived[n.id].state == "wait"]
    if waiting:
        lines.append("")
        lines.append("Waiting on others:")
        for n in waiting:
            lines.append(f"  {n.id}  {n.title}  ({derived[n.id].detail})")
    return "\n".join(lines)


def one_line(g: Graph, derived: dict[str, Derived], changed: dict[str, str], when: str) -> str:
    counts = {s: sum(1 for d in derived.values() if d.state == s) for s in STATES}
    warns = sum(len(d.warn) for d in derived.values())
    parts = " ".join(f"{s}={counts[s]}" for s in STATES if counts[s])
    return f"{when}  {g.goal}: {parts} warnings={warns} changed={len(changed)}"


# --------------------------------------------------------------------------
# CLI


def find_graph(arg: str) -> Path:
    p = Path(arg).expanduser()
    if p.suffix in (".yaml", ".yml") and p.exists():
        return p
    cand = NOTEBOOK / f"{arg}.dag.yaml"
    if cand.exists():
        return cand
    raise GraphError(f"no graph {arg!r}: {cand} does not exist (try --list)")


def cmd_list() -> int:
    files = sorted(NOTEBOOK.glob("*.dag.yaml"))
    if not files:
        print(f"no *.dag.yaml in {NOTEBOOK}")
    for f in files:
        try:
            data = yaml.safe_load(f.read_text(encoding="utf-8")) or {}
            title = data.get("title", "")
        except (OSError, yaml.YAMLError):
            title = "(not valid YAML)"
        print(f"{f.name.removesuffix('.dag.yaml')}\t{title}\t{f}")
    return 0


def cmd_check(path: Path) -> int:
    g = load_graph(path)
    errors, warnings = check_graph(g)
    for e in errors:
        print(f"error: {e}")
    for w in warnings:
        print(f"warning: {w}")
    print(
        f"{path.name}: {len(g.nodes)} nodes, {len(g.edges)} edges, "
        f"{len(errors)} errors, {len(warnings)} warnings"
    )
    return 1 if errors else 0


def cycle_once(g: Graph, src: Sources) -> tuple[dict[str, Derived], dict[str, str], bool, str, bool]:
    """Get the status, write the page and the state file.

    Returns (derived, changed, first_run, when, page_is_new)."""
    own = resolve_sources(g, src)
    derived = derive(g, own)
    last = load_last(g)
    changed = changes(last, derived)
    when = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    page_is_new = not g.output.exists()
    write_atomic(g.output, render(g, derived, changed, when, TEMPLATE.read_text(encoding="utf-8")))
    save_state(g, derived, when)
    return derived, changed, not last, when, page_is_new


def open_page(path: Path) -> None:
    if sys.platform == "darwin":
        subprocess.run(["open", str(path)], check=False)
    elif shutil.which("xdg-open"):
        subprocess.run(["xdg-open", str(path)], check=False)


def main(argv: list[str] | None = None, sources: Sources | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="action-dag",
        description="Draw the action graph of a goal, with live status from GitLab MRs, "
        "ask-zk items and read-only probes.",
    )
    ap.add_argument(
        "goal", nargs="?",
        help="the goal name (reads <notebook>/<goal>.dag.yaml), or the path to a .dag.yaml file",
    )
    ap.add_argument(
        "--no-open", action="store_true",
        help="do not open the HTML page (without this flag, the page opens only when it is new)",
    )
    ap.add_argument("--list", action="store_true", help="list the graphs in the notebook")
    ap.add_argument("--check", action="store_true", help="check the YAML only. Get no status")
    ap.add_argument(
        "--json", action="store_true", help="print the state of each node as JSON, not the summary"
    )
    ap.add_argument(
        "--watch", nargs="?", type=float, const=5.0, metavar="MINUTES",
        help="write the page again every MINUTES minutes (default 5) until Ctrl-C",
    )
    args = ap.parse_args(argv)

    if args.list:
        return cmd_list()
    if not args.goal:
        ap.error("give a goal, or --list")
    try:
        path = find_graph(args.goal)
        if args.check:
            return cmd_check(path)
        g = load_graph(path)
    except GraphError as e:
        print(f"action-dag: {e}", file=sys.stderr)
        return 2
    errors, _ = check_graph(g)
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        print("action-dag: fix the graph first (see --check)", file=sys.stderr)
        return 2

    src = sources or Sources()
    derived, changed, first_run, when, page_is_new = cycle_once(g, src)
    if args.json:
        print(json.dumps(
            {
                nid: {
                    "state": d.state, "own": d.own, "pill": d.pill, "detail": d.detail,
                    "warn": d.warn, "changed_from": changed.get(nid), "link": g.nodes[nid].link,
                }
                for nid, d in derived.items()
            },
            indent=2,
        ))
    else:
        print(summary(g, derived, changed, first_run=first_run))
        print("")
        print(f"Page: {g.output}")
    if not args.no_open and page_is_new:
        open_page(g.output)
    if args.watch is None:
        return 0

    interval = max(0.1, args.watch) * 60
    print(f"Watching: a new page every {args.watch:g} min. Stop with Ctrl-C.", flush=True)
    try:
        while True:
            time.sleep(interval)
            try:
                g = load_graph(path)
                errors, _ = check_graph(g)
                if errors:
                    print(f"{when}  the graph has errors, so the page did not change: {errors[0]}", flush=True)
                    continue
                derived, changed, _, when, _ = cycle_once(g, src)
            except (GraphError, OSError) as e:
                print(f"action-dag: {e}", file=sys.stderr, flush=True)
                continue
            print(one_line(g, derived, changed, when), flush=True)
            if changed:
                print(summary(g, derived, changed), flush=True)
    except KeyboardInterrupt:
        print("")
        return 0


if __name__ == "__main__":
    sys.exit(main())
