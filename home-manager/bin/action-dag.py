#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6", "markdown-it-py>=3", "ruamel.yaml>=0.19,<0.20"]
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
page works from file:// and as a claude.ai Artifact. JavaScript in the page
reloads it every `refresh_seconds`, so an open browser tab stays current. If
the browser does not run JavaScript, a <meta refresh> tag inside <noscript>
reloads the page. The URL hash (location.hash) and sessionStorage keep the
selected node through a reload.

`<goal>.dag.state.json`, next to the YAML file, keeps the state of each node
from the last run. The next run uses it to mark what changed.

`--public` writes a page that is safe to share outside this machine
(default `<goal>.public.dag.html`). It has no ask data, no local paths and
no zk wiki links. It does not read or write the state file. See the
"public page" comment block below.

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
import dataclasses
import difflib
import io
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
from ruamel.yaml import YAML
from ruamel.yaml.comments import CommentedMap, CommentedSeq
from ruamel.yaml.error import YAMLError as RuamelYAMLError
from ruamel.yaml.scalarstring import (
    DoubleQuotedScalarString,
    FoldedScalarString,
    LiteralScalarString,
    PlainScalarString,
    ScalarString,
    SingleQuotedScalarString,
)

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
    lane: str | None = None  # optional label. The panel shows it. It does not set the column
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
    # `lanes:` is optional and does not change the layout (see board_columns()).
    # If the file has `lanes:`, each `lane:` must be one of its ids.
    lane_ids = [ln.get("id") for ln in g.lanes]
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
        if g.lanes and n.lane is not None and n.lane not in lane_ids:
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


@dataclass
class Column:
    """One column of the board."""

    key: str  # "done", "ready" or "after-<n>"
    title: str
    sub: str
    ids: list[str]


def open_depth(g: Graph, derived: dict[str, Derived]) -> dict[str, int]:
    """Return the depth of each open node. An open node is a node that is not
    done. The depth is the number of open nodes on the longest path of open
    predecessors. 0 means that no open node comes before it. The count stops
    at a done node."""
    preds = predecessors(g)
    depth: dict[str, int] = {}

    def visit(nid: str) -> int:
        if nid not in depth:
            depth[nid] = 0  # a guard only: check_graph() refuses a cycle
            depth[nid] = max(
                (visit(p) + 1 for p in preds[nid] if derived[p].state != "done"), default=0
            )
        return depth[nid]

    for nid in g.nodes:
        if derived[nid].state != "done":
            visit(nid)
    return depth


def board_columns(g: Graph, derived: dict[str, Derived]) -> list[Column]:
    """Return the board columns, from left to right. The node states of this
    run set the columns. The YAML `lanes:` have no effect here.

    * Done: the nodes in the state `done`.
    * Ready now: the open nodes with depth 0 (see open_depth()).
    * After N steps: the open nodes with depth N.

    A column with no cards is not shown. Side tracks are not on the board.
    In a column, the cards stay in YAML order."""
    main = [n.id for n in g.nodes.values() if not n.side]
    depth = open_depth(g, derived)
    cols: list[Column] = []
    done = [i for i in main if derived[i].state == "done"]
    if done:
        cols.append(Column("done", "Done", "Finished steps", done))
    for k in range(max((depth[i] for i in main if i in depth), default=-1) + 1):
        ids = [i for i in main if depth.get(i) == k]
        if not ids:  # possible when only side tracks have depth k
            continue
        if k == 0:
            cols.append(Column("ready", "Ready now", "No open step before it", ids))
        else:
            title = f"After {k} step" + ("s" if k > 1 else "")
            cols.append(Column(f"after-{k}", title, "Waits for open steps", ids))
    return cols


# --------------------------------------------------------------------------
# files


def write_atomic(path: Path, text: str, mode: int = 0o644) -> None:
    """Write to a temporary file in the same directory, then rename it. Thus a
    browser that reloads the page never reads a half-written file."""
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, mode)
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
    # The YAML lane does not set the column. The panel shows it only as a label.
    lane = ""
    if node.lane is not None:
        titles = {ln.get("id"): ln.get("title") or ln.get("id") for ln in g.lanes}
        lane = f'<p class="laneline">Lane: {esc(titles.get(node.lane, node.lane))}</p>'
    return (
        f'<template id="p-{esc(node.id)}">'
        f'<p class="id">{esc(id_row(node))}{owner}</p>'
        f'<h3 tabindex="-1">{esc(node.title)}</h3>'
        f'<p class="state s-{d.state}"><span class="pill">{esc(d.pill)}</span> {esc(d.detail)}</p>'
        f"{changed}{warn}"
        + (f'<p class="sub">{esc(node.sub)}</p>' if node.sub else "")
        + lane
        + (f'<div class="btns">{btns}</div>' if btns else "")
        + '<div class="rel"><span>Waits on</span>'
        + f"<div>{chips(preds[node.id], derived, g)}</div>"
        + "<span>Unblocks</span>"
        + f"<div>{chips(succs[node.id], derived, g)}</div></div>"
        + notes
        + "".join(fact_html(f) for f in d.facts)
        + "</template>"
    )


def render(
    g: Graph, derived: dict[str, Derived], changed: dict[str, str], when: str, template: str,
    public: bool = False,
) -> str:
    cols = board_columns(g, derived)
    cols_html = []
    for col in cols:
        cards = "".join(card(g.nodes[i], derived[i], changed.get(i)) for i in col.ids)
        cols_html.append(
            f'<section class="col col-{col.key.split("-")[0]}" data-col="{esc(col.key)}">'
            f"<h2>{esc(col.title)}<small>{esc(col.sub)}</small></h2>{cards}</section>"
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
        f'<noscript><meta http-equiv="refresh" content="{g.refresh}"></noscript>' if g.refresh else ""
    )
    reload_txt = f" · reloads every {g.refresh} s" if g.refresh else ""
    # json.dumps output sits in a <script>: escape "</" so it cannot close it.
    edges_json = json.dumps(edges).replace("</", "<\\/")
    if public:
        # The --public self-check refuses a page that contains "[[" (a zk wiki
        # link). A space between the brackets keeps the JSON valid.
        edges_json = edges_json.replace("[[", "[ [")
    repl = {
        "{{REFRESH}}": refresh,
        "{{RELOAD_SECONDS}}": str(g.refresh),
        "{{TITLE}}": esc(g.title),
        "{{SUMMARY}}": esc(g.summary),
        "{{GENERATED}}": esc(when),
        "{{META}}": esc(
            f"from {g.path.name}{reload_txt} · {count_txt} · "
            'arrows mean "must finish before" · '
            "the column of a card counts the open steps on the longest path before it · "
            "select a card for its details"
        ),
        "{{COLUMNS}}": str(max(1, len(cols))),
        "{{BOARD}}": "\n".join(cols_html),
        "{{DONE}}": done_html,
        "{{SIDE}}": side_html,
        "{{PANELS}}": panels,
        "{{STORAGE_KEY}}": esc(f"action-dag:{g.goal}"),
        "{{EDGES_JSON}}": edges_json,
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


# --------------------------------------------------------------------------
# public page (--public)
#
# `action-dag <goal> --public` writes a page that is safe to share outside
# this machine, for example as an Asana attachment. The normal page contains
# the ask notes and local file paths. The public page:
#
#   * removes all ask data: the ask panels, the ask ids on the cards, the
#     `asks:` lists and the ask warnings. A node keeps the state that its ask
#     gives, but its detail says only "private note open" (or closed, ...).
#   * replaces each local path (under the home directory, `~/`, `$HOME`) with
#     "[local path]".
#   * replaces each zk wiki link with its label: `[[id|label]]` gives `label`,
#     and `[[id]]` gives nothing.
#   * removes the matches of each --redact-pattern from the text of the page
#     (titles, subtitles, notes, details, warnings, MR titles, probe text).
#     URLs keep their matches, so the links still work.
#   * turns off the browser reload, and shows no "changed since the last run"
#     marks.
#
# It never writes the state file and never opens the page. Before it writes,
# it checks the page again (public_leaks()). If the home directory path,
# `~/` or `[[` is still in the page, it writes nothing and exits 1.

LOCAL_PATH = "[local path]"
# [[id]] or [[id|label]]
WIKI_LINK = re.compile(r"\[\[([^\[\]|]*)(?:\|([^\[\]]*))?\]\]")
# The ask details that ask_result() makes, for example "ask ab12 open".
ASK_DETAIL = re.compile(r"^ask \S+ (open|closed|not found|was dropped)$")


def local_path_re() -> re.Pattern:
    """Matches a path under the home directory, in any of its usual forms.
    It reads $HOME at call time, so tests can change it."""
    home = str(Path.home()).rstrip("/")
    roots = [r"/Users/[\w.-]+", r"/home/[\w.-]+", r"~(?=/)", r"\$HOME\b", r"\$\{HOME\}"]
    if len(home) > 1:
        roots.insert(0, re.escape(home) + r"(?![\w.-])")
    return re.compile(rf"(?:file://)?(?:{'|'.join(roots)})(?:/[^\s'\"<>()\[\]`]*)?")


@dataclass
class Scrub:
    """Removes the private text and counts each removal."""

    patterns: list[re.Pattern] = field(default_factory=list)
    asks: int = 0
    ask_warnings: int = 0
    paths: int = 0
    wiki: int = 0
    redacted: int = 0

    def __post_init__(self) -> None:
        self._path_re = local_path_re()

    def url(self, s: str) -> str:
        s, n = self._path_re.subn(LOCAL_PATH, s or "")
        self.paths += n
        return s

    def text(self, s) -> str:
        s = "" if s is None else str(s)
        s, n = WIKI_LINK.subn(lambda m: (m.group(2) or "").strip(), s)
        self.wiki += n
        s = self.url(s)
        for pat in self.patterns:
            s, n = pat.subn("", s)
            self.redacted += n
        return s

    def line(self) -> str:
        return (
            f"Public page: removed {self.asks} ask references, {self.ask_warnings} ask warnings, "
            f"{self.paths} local paths, {self.wiki} wiki links and {self.redacted} "
            "--redact-pattern matches. Browser reload off. No state file written."
        )


def public_fact(f: dict, s: Scrub) -> dict:
    f = dict(f)
    for key in ("title", "cmd", "stderr", "error"):
        if f.get(key):
            f[key] = s.text(f[key])
    for key in ("url", "pipeline_url"):
        if f.get(key):
            f[key] = s.url(f[key])
    return f


def public_result(r: Result, s: Scrub) -> Result:
    """A copy of one node's result with no ask data and no private text."""
    warn = []
    for w in r.warn:
        if w.startswith("ask "):  # all ask warnings start with "ask " (ask_result, combine)
            s.ask_warnings += 1
        else:
            warn.append(s.text(w))
    m = ASK_DETAIL.match(r.detail)
    if m:
        detail = f"private note {m.group(1)}"
    elif r.detail.startswith("ask-zk "):  # the ask-zk call failed
        detail = "private note: lookup failed"
    else:
        detail = s.text(r.detail)
    facts = [public_fact(f, s) for f in r.facts if f["kind"] != "ask"]
    return dataclasses.replace(r, detail=detail, warn=warn, facts=facts)


def public_graph(g: Graph, s: Scrub) -> Graph:
    """A copy of the graph with no ask references and no private text. The
    node sources keep their mr, probe and manual entries for the id row."""
    nodes = {}
    for nid, n in g.nodes.items():
        s.asks += len(n.asks) + sum(1 for src in n.sources if "ask" in src)
        nodes[nid] = dataclasses.replace(
            n,
            title=s.text(n.title),
            sub=s.text(n.sub),
            notes=s.text(n.notes),
            tag=s.text(n.tag),
            owner=s.text(n.owner),
            link=s.url(n.link),
            links=[{"label": s.text(x["label"]), "url": s.url(x["url"])} for x in n.links],
            asks=[],
            sources=[src for src in n.sources if "ask" not in src],
        )
    lanes = [
        {**ln, **{k: s.text(ln[k]) for k in ("title", "sub") if ln.get(k)}} for ln in g.lanes
    ]
    done = [
        {**d, "label": s.text(d.get("label", "")), **({"link": s.url(d["link"])} if d.get("link") else {})}
        for d in g.done
    ]
    return dataclasses.replace(
        g, title=s.text(g.title), summary=s.text(g.summary), lanes=lanes, nodes=nodes,
        done=done, refresh=0,
    )


def public_leaks(page: str) -> list[str]:
    """The private text that the self-check finds in a page. An empty list
    means that the check passed."""
    leaks = []
    home = str(Path.home()).rstrip("/")
    if len(home) > 1 and home in page:
        leaks.append(f"the home directory path {home}")
    if "~/" in page:
        leaks.append("a ~/ path")
    if "[[" in page:
        leaks.append("a wiki link ([[)")
    return leaks


def cmd_public(g: Graph, src: Sources, output: Path | None, patterns: list[re.Pattern]) -> int:
    """Write the public page. Never writes the state file or opens the page."""
    out = output or g.path.with_name(f"{g.goal}.public.dag.html")
    if out.suffix not in (".html", ".htm"):
        print(f"action-dag: --output must end in .html or .htm: {out}", file=sys.stderr)
        return 2
    s = Scrub(patterns)
    own = resolve_sources(g, src)
    pg = public_graph(g, s)
    derived = derive(pg, {nid: public_result(r, s) for nid, r in own.items()})
    when = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    page = render(pg, derived, {}, when, TEMPLATE.read_text(encoding="utf-8"), public=True)
    leaks = public_leaks(page)
    if leaks:
        print(
            f"action-dag: the public page still contains {'; '.join(leaks)}. "
            "Nothing was written.",
            file=sys.stderr,
        )
        return 1
    out.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(out, page)
    print(s.line())
    print(f"Page: {out}")
    return 0


# --------------------------------------------------------------------------
# editing (set, add, edge, done, rm)
#
# The editing commands change the YAML file with ruamel.yaml in round-trip
# mode, so the comments, the key order, the quotes and the blank lines outside
# the edited node stay the same. Each command checks the result with
# check_graph() before it writes, writes atomically, and then writes the page
# again (as `action-dag <goal> --no-open` does) unless --no-render is given.


EDIT_COMMANDS = ("set", "add", "edge", "done", "rm")
# The order of the keys in a node. A new key goes after the nearest key that
# comes before it in this order.
KEY_ORDER = (
    "id", "lane", "title", "sub", "link", "owner", "status", "asks",
    "hold_until", "tag", "links", "notes",
)
# Plain string fields: (option dest, YAML key).
FIELD_OPTS = (
    ("title", "title"), ("sub", "sub"), ("link", "link"), ("owner", "owner"),
    ("lane", "lane"), ("hold_until", "hold_until"), ("tag", "tag"),
)
# (mapping, sequence, offset) indents to try. load_doc() uses the first one
# that gives the file back byte for byte.
INDENTS = ((2, 4, 2), (2, 2, 0), (4, 4, 2), (4, 6, 4), (4, 4, 0))
BLOCK_SCALARS = (LiteralScalarString, FoldedScalarString)


class EditError(Exception):
    """The edit is refused. Nothing was written."""


def rt_yaml(indent: tuple[int, int, int]) -> YAML:
    y = YAML()  # round-trip mode
    y.preserve_quotes = True
    y.width = 4096  # never fold a long line (probe commands are long)
    y.indent(mapping=indent[0], sequence=indent[1], offset=indent[2])
    return y


def rt_dump(y: YAML, data) -> str:
    buf = io.StringIO()
    y.dump(data, buf)
    return buf.getvalue()


@dataclass
class Doc:
    """A graph file loaded in round-trip mode."""

    path: Path
    text: str
    data: CommentedMap
    yaml: YAML
    exact: bool  # True if a dump without edits gives the same bytes

    def dump(self) -> str:
        return rt_dump(self.yaml, self.data)


def load_doc(path: Path) -> Doc:
    text = path.read_text(encoding="utf-8")
    first: tuple[YAML, CommentedMap] | None = None
    for indent in INDENTS:
        y = rt_yaml(indent)
        try:
            data = y.load(text)
        except RuamelYAMLError as e:
            raise GraphError(f"{path}: not valid YAML: {e}") from e
        if not isinstance(data, CommentedMap):
            raise GraphError(f"{path}: the top level must be a mapping")
        if rt_dump(y, data) == text:
            return Doc(path, text, data, y, True)
        if first is None:
            first = (y, data)
    assert first is not None
    return Doc(path, text, first[1], first[0], False)


def ystr(value: str):
    """A new string value. Quote it when PyYAML (which reads the graph) would
    read the plain form as something else: `yes` is a bool, `0123` an int."""
    try:
        plain_ok = yaml.safe_load(value) == value
    except yaml.YAMLError:
        plain_ok = False
    # The characters ,[]{} end a plain value in a flow collection (`[a, b]`).
    if plain_ok and value == value.strip() and not re.search(r"[\n,\[\]{}]", value):
        return value
    return DoubleQuotedScalarString(value)


def like(old, value: str):
    """A new value for a key. Keep the quote style of the old value."""
    if "\n" in value:
        return LiteralScalarString(value if value.endswith("\n") else value + "\n")
    if isinstance(old, DoubleQuotedScalarString):
        return DoubleQuotedScalarString(value)
    if isinstance(old, SingleQuotedScalarString) and "\n" not in value:
        return SingleQuotedScalarString(value)
    return ystr(value)


def flow_map(**kw) -> CommentedMap:
    m = CommentedMap()
    for k, v in kw.items():
        m[k] = v
    m.fa.set_flow_style()
    return m


def flow_seq(items) -> CommentedSeq:
    s = CommentedSeq(items)
    s.fa.set_flow_style()
    return s


# ---- comment bookkeeping
#
# ruamel.yaml keeps the blank lines and comments after the last key of a
# mapping on that key (ca.items[key][2]). When a key is added after it, or the
# last key is removed, these lines must move to the new last key, or the blank
# line between two nodes moves or goes away. After a plain value the token
# starts with the end of the value's own line ("# comment\n" or "\n"); after a
# block scalar (`|`) it does not.


def _tail(cm: CommentedMap, key):
    item = cm.ca.items.get(key)
    return item[2] if item and len(item) > 2 else None


def _split_tail(cm: CommentedMap, key) -> tuple[str, str]:
    """(own, rest) of the comment after key: own is the comment on the value's
    own line, rest is the lines after it."""
    tok = _tail(cm, key)
    if tok is None:
        return "", ""
    value = tok.value
    if isinstance(cm.get(key), BLOCK_SCALARS):
        return "", value
    head, nl, rest = value.partition("\n")
    return head + nl, rest


def _put_tail(cm: CommentedMap, key, own: str, rest: str) -> None:
    """Set the comment after key from its parts. own is ignored after a block
    scalar."""
    from ruamel.yaml.tokens import CommentToken
    from ruamel.yaml.error import CommentMark

    if isinstance(cm.get(key), BLOCK_SCALARS):
        value = rest
    else:
        value = (own or "\n") + rest if rest else (own if own.strip() else "")
    item = cm.ca.items.setdefault(key, [None, None, None, None])
    while len(item) < 4:
        item.append(None)
    item[2] = CommentToken(value, CommentMark(0), None) if value else None


def _last_key(cm: CommentedMap):
    return next(reversed(cm)) if len(cm) else None


def set_key(cm: CommentedMap, key: str, value) -> None:
    """Set key. A new key goes to its place in KEY_ORDER. The lines after the
    old last key move to the new last key."""
    if key in cm:
        last = _last_key(cm) == key
        own, rest = _split_tail(cm, key) if last else ("", "")
        if type(value) is str and isinstance(cm[key], ScalarString):
            # ruamel.yaml gives a plain str the style of the old value (a `|`
            # block, quotes). PlainScalarString keeps the new value plain.
            value = PlainScalarString(value)
        cm[key] = value
        if last:  # the value can change from plain to block, or back
            _put_tail(cm, key, own, rest)
        return
    rank = KEY_ORDER.index(key) if key in KEY_ORDER else len(KEY_ORDER)
    pos = 0
    for i, k in enumerate(cm):
        if (KEY_ORDER.index(k) if k in KEY_ORDER else len(KEY_ORDER)) <= rank:
            pos = i + 1
    old_last = _last_key(cm)
    cm.insert(pos, key, value)
    if old_last is not None and _last_key(cm) == key:
        own, rest = _split_tail(cm, old_last)
        _put_tail(cm, old_last, own, "")
        _put_tail(cm, key, "", rest)


def del_key(cm: CommentedMap, key: str) -> None:
    if key not in cm:
        return
    keys = list(cm)
    if keys[-1] == key and len(keys) > 1:
        _, rest = _split_tail(cm, key)
        prev = keys[-2]
        own, _ = _split_tail(cm, prev)
        del cm[key]
        cm.ca.items.pop(key, None)
        _put_tail(cm, prev, own, rest)
    else:
        del cm[key]
        cm.ca.items.pop(key, None)


def del_item(seq: CommentedSeq, i: int) -> None:
    """Remove seq[i]. The comment lines before the item (for example a lane
    heading) move to the next item, if that item has none."""
    item = seq.ca.items.get(i)
    pre = item[1] if item and len(item) > 1 else None
    del seq[i]  # ruamel.yaml moves the comments of the later items
    if i >= len(seq):
        return
    item = seq.ca.items.setdefault(i, [None, None, None, None])
    if pre and not item[1]:
        item[1] = pre
    elif item[1] and i > 0 and _ends_blank(seq[i - 1]) and item[1][0].value == "\n":
        # The item before and the item after both have a blank line between
        # them and the removed item. Keep one blank line, not two.
        item[1] = item[1][1:] or None


def _ends_blank(obj) -> bool:
    """True if a blank line follows obj (in the comment on its last key)."""
    while isinstance(obj, CommentedMap) and len(obj):
        key = _last_key(obj)
        if _split_tail(obj, key)[1].startswith("\n"):
            return True
        obj = obj[key]
    return False


# ---- finding things


def node_lists(data: CommentedMap):
    for key in ("nodes", "side"):
        seq = data.get(key)
        if isinstance(seq, list):
            yield key, seq


def find_node(data: CommentedMap, nid: str) -> tuple[str, int, CommentedMap]:
    for key, seq in node_lists(data):
        for i, raw in enumerate(seq):
            if isinstance(raw, dict) and str(raw.get("id")) == nid:
                return key, i, raw
    raise EditError(f"no node {nid!r} in the graph")


def edge_list(data: CommentedMap, create: bool = False) -> CommentedSeq | None:
    seq = data.get("edges")
    if seq is None and create:
        seq = CommentedSeq()
        top_insert(data, "edges", seq, after=("side", "nodes"))
    return seq


def top_insert(data: CommentedMap, key: str, value, after: tuple[str, ...]) -> None:
    """Add a top-level key after the first key in `after` that exists."""
    for a in after:
        if a in data:
            pos = list(data).index(a) + 1
            old_last = _last_key(data)
            data.insert(pos, key, value)
            if _last_key(data) == key and old_last is not None:
                own, rest = _split_tail(data, old_last)
                _put_tail(data, old_last, own, "")
                _put_tail(data, key, "", rest)
            return
    data[key] = value


def edges_of(data: CommentedMap) -> list[tuple[str, str]]:
    return [(str(e[0]), str(e[1])) for e in (data.get("edges") or []) if isinstance(e, list) and len(e) == 2]


# ---- status arguments


def parse_status_arg(text: str, defaults: dict, pending: str | None):
    """One --status value as a source mapping:
    ask:<id>, mr:<iid>, mr:<project>!<iid>, mr:<MR URL>, probe:<cmd> or
    manual:<state>."""
    kind, sep, value = text.partition(":")
    kind = kind.strip()
    if not sep or kind not in SOURCE_KEYS or not value.strip():
        raise EditError(
            f"--status {text!r}: use ask:<id>, mr:<iid>, mr:<project>!<iid>, "
            "probe:<cmd> or manual:<state>"
        )
    value = value.strip()
    if kind == "ask":
        return flow_map(ask=ystr(value))
    if kind == "manual":
        return flow_map(manual=value)
    if kind == "probe":
        m = flow_map(probe=ystr(value))
        if pending:
            m["pending"] = pending
        return m
    # mr
    host = project = None
    url = re.fullmatch(r"https://([^/]+)/(.+?)/-/merge_requests/(\d+)/?", value)
    if url:
        host, project, iid = url.group(1), url.group(2), url.group(3)
    elif "!" in value:
        project, _, iid = value.rpartition("!")
    else:
        iid = value
    if not iid.isdigit():
        raise EditError(f"--status {text!r}: the MR iid must be a number")
    if host == defaults.get("mr_host", "gitlab.com"):
        host = None
    if project == defaults.get("mr_project"):
        project = None
    if not host and not project:
        if not defaults.get("mr_project"):
            raise EditError(f"--status {text!r}: no defaults.mr_project, so give mr:<project>!<iid>")
        return flow_map(mr=int(iid))
    mr = flow_map(project=ystr(project or defaults.get("mr_project", "")), iid=int(iid))
    if host:
        mr["host"] = host
    return flow_map(mr=mr)


def status_value(sources: list):
    """One source: a flow mapping, `{ask: ab12}`. Several: a block list."""
    if len(sources) == 1:
        return sources[0]
    seq = CommentedSeq()
    for s in sources:
        s.fa.set_block_style()
        seq.append(s)
    return seq


def source_text(sources: list) -> str:
    """A short text for the new status sources, for the summary line."""
    out = []
    for s in sources:
        kind = next(iter(s))
        value = s[kind]
        if kind == "mr" and isinstance(value, dict):
            value = f"{value.get('host', '') + '/' if value.get('host') else ''}{value['project']}!{value['iid']}"
        elif kind == "probe":
            value = short(str(value), 30)
        out.append(f"{kind}:{value}")
    return " + ".join(out)


# ---- applying the node options


def apply_node_opts(cm: CommentedMap, args, defaults: dict, changes: list[str]) -> None:
    """Apply the options that set, add and done share. Append a short text
    to `changes` for each change."""
    for dest, key in FIELD_OPTS:
        value = getattr(args, dest, None)
        if value is None:
            continue
        old = cm.get(key)
        if value == "":
            if key in cm:
                del_key(cm, key)
                changes.append(f"{key} removed")
            continue
        if old is not None and str(old) == value:
            continue
        set_key(cm, key, like(old, value))
        changes.append(f"{key} {short(value)!r}")

    if args.state and args.status:
        raise EditError("give --state or --status, not both")
    if args.pending and not any(s.startswith("probe:") for s in args.status or []):
        raise EditError("--pending needs a --status probe:<cmd>")
    if args.state:
        old = cm.get("status")
        value = flow_map(manual=args.state)
        if not (isinstance(old, dict) and dict(old) == {"manual": args.state}) and old != args.state:
            set_key(cm, "status", value)
            changes.append(f"state {args.state}")
    elif args.status:
        sources = [parse_status_arg(s, defaults, args.pending) for s in args.status]
        set_key(cm, "status", status_value(sources))
        changes.append(f"status {source_text(sources)}")

    add = [a for a in (getattr(args, "add_ask", None) or [])]
    remove = [a for a in (getattr(args, "remove_ask", None) or [])]
    if add or remove:
        asks = cm.get("asks")
        if isinstance(asks, str):
            asks = flow_seq([asks])
        elif asks is None:
            asks = flow_seq([])
        current = [str(a) for a in asks]
        for a in remove:
            if a not in current:
                raise EditError(f"node {cm.get('id')}: ask {a} is not in asks {current}")
            idx = current.index(a)
            del asks[idx]
            current.pop(idx)
            changes.append(f"asks -{a}")
        for a in add:
            if a in current:
                continue
            asks.append(ystr(a))
            current.append(a)
            changes.append(f"asks +{a}")
        if current:
            set_key(cm, "asks", asks)
        else:
            del_key(cm, "asks")

    if args.note is not None and args.append_note is not None:
        raise EditError("give --note or --append-note, not both")
    if args.note is not None:
        if args.note == "":
            if "notes" in cm:
                del_key(cm, "notes")
                changes.append("notes removed")
        else:
            set_key(cm, "notes", like(cm.get("notes"), args.note))
            changes.append("notes replaced")
    elif args.append_note:
        old = str(cm.get("notes") or "")
        text = (old.rstrip("\n") + "\n" + args.append_note) if old.strip() else args.append_note
        set_key(cm, "notes", like(cm.get("notes"), text))
        changes.append("notes appended")


def short(text: str, n: int = 40) -> str:
    text = " ".join(text.split())
    return text if len(text) <= n else text[: n - 1] + "…"


# ---- the commands


def edit_set(doc: Doc, args, src) -> list[str]:
    _, _, cm = find_node(doc.data, args.node)
    changes: list[str] = []
    apply_node_opts(cm, args, doc.data.get("defaults") or {}, changes)
    return [f"set {args.node}: " + ", ".join(changes)] if changes else []


def edit_add(doc: Doc, args, src) -> list[str]:
    try:
        find_node(doc.data, args.node)
    except EditError:
        pass
    else:
        raise EditError(f"node {args.node!r} is already in the graph (use set)")
    if args.side and args.lane:
        raise EditError("a side node has no lane: give --side or --lane, not both")
    if not args.title:
        raise EditError("give --title")
    cm = CommentedMap()
    cm["id"] = ystr(args.node)
    changes: list[str] = []
    apply_node_opts(cm, args, doc.data.get("defaults") or {}, changes)
    if "status" not in cm:
        set_key(cm, "status", flow_map(manual="next"))
    key = "side" if args.side else "nodes"
    seq = doc.data.get(key)
    if seq is None:
        seq = CommentedSeq()
        top_insert(doc.data, key, seq, after=("done", "edges", "nodes", "lanes") if key == "side" else ("lanes",))
    pos = len(seq)
    if args.lane:
        # After the last node of the same lane, so the YAML stays in lane order.
        same = [i for i, n in enumerate(seq) if isinstance(n, dict) and n.get("lane") == args.lane]
        if same:
            pos = same[-1] + 1
    seq.insert(pos, cm)
    added = []
    for pred in args.after or []:
        added.append(add_edge(doc.data, pred, args.node))
    for succ in args.before or []:
        added.append(add_edge(doc.data, args.node, succ))
    where = " (side)" if args.side else f" (lane {args.lane})" if args.lane else ""
    line = f"add {args.node}{where}"
    if added:
        line += ", edges " + ", ".join(f"[{a}, {b}]" for a, b in added)
    return [line]


def add_edge(data: CommentedMap, a: str, b: str, pos: int | None = None) -> tuple[str, str]:
    if (a, b) in edges_of(data):
        raise EditError(f"edge [{a}, {b}] is already in the graph")
    seq = edge_list(data, create=True)
    item = flow_seq([ystr(a), ystr(b)])
    if pos is None:
        seq.append(item)
    else:
        seq.insert(pos, item)
    return a, b


def edit_edge(doc: Doc, args, src) -> list[str]:
    a, b = args.a, args.b
    if args.remove:
        seq = doc.data.get("edges") or []
        for i, e in enumerate(seq):
            if isinstance(e, list) and len(e) == 2 and (str(e[0]), str(e[1])) == (a, b):
                del_item(seq, i)
                return [f"edge [{a}, {b}] removed"]
        raise EditError(f"no edge [{a}, {b}] in the graph")
    add_edge(doc.data, a, b)
    return [f"edge [{a}, {b}] added"]


def drop_edges_of(data: CommentedMap, nid: str) -> tuple[list[tuple[str, str]], int | None]:
    """Remove each edge to or from nid. Returns (removed, index of the first)."""
    seq = data.get("edges") or []
    removed, first = [], None
    for i in reversed(range(len(seq))):
        e = seq[i]
        if isinstance(e, list) and len(e) == 2 and nid in (str(e[0]), str(e[1])):
            removed.insert(0, (str(e[0]), str(e[1])))
            first = i
            del_item(seq, i)
    return removed, first


def node_state(doc: Doc, nid: str, src) -> Result:
    """The state that the node's own sources give now (live lookup)."""
    g = graph_from_dict(doc.data, doc.path)
    one = dataclasses.replace(g, nodes={nid: g.nodes[nid]}, edges=[])
    return resolve_sources(one, src)[nid]


def edit_done(doc: Doc, args, src) -> list[str]:
    key, idx, cm = find_node(doc.data, args.node)
    if not args.force:
        r = node_state(doc, args.node, src)
        if r.state != "done":
            raise EditError(
                f"node {args.node} is {r.state} ({r.detail}), not done. "
                "Give --force to move it to the done row anyway"
            )
    g = graph_from_dict(doc.data, doc.path)
    link = args.link if args.link is not None else g.nodes[args.node].link
    holders = [n.id for n in g.nodes.values() if n.hold_until == args.node]
    for h in holders:
        _, _, hcm = find_node(doc.data, h)
        del_key(hcm, "hold_until")
    removed, first = drop_edges_of(doc.data, args.node)
    preds = [a for a, b in removed if b == args.node]
    succs = [b for a, b in removed if a == args.node]
    # Keep the order: each predecessor of the node goes before each successor.
    bridged = []
    pos = first
    for p in preds:
        for s in succs:
            if p != s and (p, s) not in edges_of(doc.data):
                add_edge(doc.data, p, s, pos)
                bridged.append((p, s))
                pos = (pos + 1) if pos is not None else None
    del_item(doc.data[key], idx)
    entry = flow_map(label=DoubleQuotedScalarString(args.label))
    if link:
        entry["link"] = DoubleQuotedScalarString(link)
    done = doc.data.get("done")
    if done is None:
        done = CommentedSeq()
        top_insert(doc.data, "done", done, after=("edges", "nodes"))
    done.append(entry)
    line = f"done {args.node}: moved to the done row as {short(args.label)!r}"
    if removed:
        line += ", edges removed " + ", ".join(f"[{a}, {b}]" for a, b in removed)
    if bridged:
        line += ", edges added " + ", ".join(f"[{a}, {b}]" for a, b in bridged)
    if holders:
        line += ", hold_until removed from " + ", ".join(holders)
    return [line]


def edit_rm(doc: Doc, args, src) -> list[str]:
    key, idx, _ = find_node(doc.data, args.node)
    refs = [e for e in edges_of(doc.data) if args.node in e]
    g = graph_from_dict(doc.data, doc.path)
    holders = [n.id for n in g.nodes.values() if n.hold_until == args.node]
    if (refs or holders) and not args.force:
        what = [f"edges {', '.join(f'[{a}, {b}]' for a, b in refs)}"] if refs else []
        what += [f"hold_until of {', '.join(holders)}"] if holders else []
        raise EditError(
            f"{' and '.join(what)} use node {args.node}. "
            "Give --force to remove them too"
        )
    removed, _ = drop_edges_of(doc.data, args.node)
    for h in holders:
        _, _, hcm = find_node(doc.data, h)
        del_key(hcm, "hold_until")
    del_item(doc.data[key], idx)
    line = f"rm {args.node}"
    if removed:
        line += ", edges removed " + ", ".join(f"[{a}, {b}]" for a, b in removed)
    if holders:
        line += ", hold_until removed from " + ", ".join(holders)
    return [line]


EDITORS = {"set": edit_set, "add": edit_add, "edge": edit_edge, "done": edit_done, "rm": edit_rm}


def render_page(path: Path, src) -> None:
    """Write the page and the state file again, as `action-dag <goal>
    --no-open` does, and print the summary. Never opens a browser tab."""
    g = load_graph(path)
    derived, changed, first_run, _, _ = cycle_once(g, src)
    print("")
    print(summary(g, derived, changed, first_run=first_run))
    print("")
    print(f"Page: {g.output}")


def edit_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--dry-run", action="store_true",
        help="print the change as a unified diff. Write nothing",
    )
    common.add_argument(
        "--no-render", action="store_true",
        help="write the YAML file, but not the page. Use it for a series of edits, "
        "then run `action-dag <goal> --no-open` once",
    )

    fields = argparse.ArgumentParser(add_help=False)
    g = fields.add_argument_group("node fields (an empty value removes the key)")
    g.add_argument("--title")
    g.add_argument("--sub")
    g.add_argument("--link", help="a full https:// URL")
    g.add_argument("--owner", help="me, a name, or empty")
    g.add_argument(
        "--lane",
        help="optional label: a lane id from `lanes:`. The panel shows it. It does not set the column",
    )
    g.add_argument("--hold-until", metavar="NODE", help="warn if the MR merges before NODE is done")
    g.add_argument("--tag", help="extra text in the card's id row")
    s = fields.add_argument_group("status")
    s.add_argument(
        "--state", choices=MANUAL_STATES,
        help="set `status: {manual: STATE}`",
    )
    s.add_argument(
        "--status", action="append", metavar="SOURCE",
        help="replace the status source: ask:<id>, mr:<iid>, mr:<project>!<iid>, "
        "mr:<MR URL>, probe:<read-only command> or manual:<state>. "
        "Give it more than once for a list of sources",
    )
    s.add_argument(
        "--pending", choices=MANUAL_STATES,
        help="the state while a --status probe fails (default next)",
    )
    s.add_argument("--add-ask", action="append", metavar="ID", help="add a related ask to `asks:`")
    n = fields.add_argument_group("notes (markdown)")
    n.add_argument("--note", help="replace `notes:`. An empty value removes it")
    n.add_argument("--append-note", metavar="TEXT", help="add TEXT on a new line at the end of `notes:`")

    ap = argparse.ArgumentParser(
        prog="action-dag",
        description="Edit a graph file. Each command checks the result (as --check does) "
        "and refuses to write a graph with errors. Then it writes the page again, "
        "as `action-dag <goal> --no-open` does, unless you give --no-render.",
    )
    sub = ap.add_subparsers(dest="cmd", required=True, metavar="COMMAND")
    goal_help = "the goal name, or the path to a .dag.yaml file"

    p = sub.add_parser("set", parents=[common, fields], help="change a node")
    p.add_argument("goal", help=goal_help)
    p.add_argument("node")
    p.add_argument("--remove-ask", action="append", metavar="ID", help="remove an ask from `asks:`")

    p = sub.add_parser(
        "add", parents=[common, fields],
        help="add a node (default status: {manual: next})",
    )
    p.add_argument("goal", help=goal_help)
    p.add_argument("node")
    p.add_argument("--side", action="store_true", help="add a side track (no lane, no edges)")
    p.add_argument("--after", action="append", metavar="NODE", help="also add the edge [NODE, new node]")
    p.add_argument("--before", action="append", metavar="NODE", help="also add the edge [new node, NODE]")

    p = sub.add_parser("edge", parents=[common], help="add or remove the edge [A, B] (A must finish before B)")
    p.add_argument("goal", help=goal_help)
    p.add_argument("a", metavar="A")
    p.add_argument("b", metavar="B")
    p.add_argument("--remove", action="store_true", help="remove the edge")

    p = sub.add_parser(
        "done", parents=[common],
        help="move a finished node to the done row",
        description="Move a finished node to the `done:` row. The command removes each edge "
        "to or from the node, and adds an edge from each predecessor to each successor, "
        "so the order stays. It refuses if the node's own sources do not say done now.",
    )
    p.add_argument("goal", help=goal_help)
    p.add_argument("node")
    p.add_argument("--label", required=True, help="the text of the link in the done row")
    p.add_argument("--link", help="the URL of the link (default: the node's link)")
    p.add_argument("--force", action="store_true", help="move the node even if it is not done")

    p = sub.add_parser("rm", parents=[common], help="remove a node")
    p.add_argument("goal", help=goal_help)
    p.add_argument("node")
    p.add_argument(
        "--force", action="store_true",
        help="also remove the edges and hold_until keys that use the node",
    )
    return ap


def edit_main(argv: list[str], sources: Sources | None = None) -> int:
    args = edit_parser().parse_args(argv)
    for name in ("state", "status", "pending", "add_ask", "note", "append_note", "remove_ask"):
        if not hasattr(args, name):
            setattr(args, name, None)
    src = sources or Sources()
    try:
        path = find_graph(args.goal)
        doc = load_doc(path)
        try:
            _, before_warn = check_graph(graph_from_dict(yaml.safe_load(doc.text) or {}, path))
        except GraphError:
            before_warn = []  # an edit can repair a graph that does not load
        changes = EDITORS[args.cmd](doc, args, src)
        new_text = doc.dump()
        try:
            after_g = graph_from_dict(yaml.safe_load(new_text) or {}, path)
        except (GraphError, yaml.YAMLError) as e:
            raise EditError(f"the result is not a valid graph: {e}") from e
        errors, warnings = check_graph(after_g)
    except GraphError as e:
        print(f"action-dag: {e}", file=sys.stderr)
        return 2
    except EditError as e:
        print(f"action-dag: {e}. Nothing was written.", file=sys.stderr)
        return 1
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        print(
            f"action-dag: the result has {len(errors)} error(s), so {path.name} did not change",
            file=sys.stderr,
        )
        return 1
    for w in warnings:
        if w not in before_warn:
            print(f"warning: {w}", file=sys.stderr)
    if new_text == doc.text:
        print(f"action-dag: no change to {path.name}")
        return 0
    old_lines, new_lines = doc.text.splitlines(keepends=True), new_text.splitlines(keepends=True)
    diff = list(difflib.unified_diff(old_lines, new_lines, fromfile=str(path), tofile=str(path)))
    plus = sum(1 for d in diff if d.startswith("+") and not d.startswith("+++"))
    minus = sum(1 for d in diff if d.startswith("-") and not d.startswith("---"))
    line = f"{path.name}: {'; '.join(changes)} (+{plus} -{minus} lines)"
    if not doc.exact:
        print(
            "warning: ruamel.yaml does not give this file back byte for byte, so the diff "
            "can show changes outside the edit. Check it with --dry-run",
            file=sys.stderr,
        )
    if args.dry_run:
        sys.stdout.writelines(diff)
        print(f"dry run, nothing written: {line}")
        return 0
    target = path.resolve()  # write through a symlink, do not replace it
    if target.read_text(encoding="utf-8") != doc.text:
        print(
            f"action-dag: {path.name} changed while this command ran. Nothing was written. "
            "Run the command again",
            file=sys.stderr,
        )
        return 1
    write_atomic(target, new_text, mode=target.stat().st_mode & 0o777)
    print(line)
    if args.no_render:
        return 0
    try:
        render_page(path, src)
    except (GraphError, OSError) as e:
        print(f"action-dag: {path.name} was written, but the page was not written: {e}", file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None, sources: Sources | None = None) -> int:
    argv = sys.argv[1:] if argv is None else list(argv)
    # The first argument selects an editing command. To render a goal that has
    # the name of a command, put an option or `--` first: `action-dag -- set`.
    if argv and argv[0] in EDIT_COMMANDS:
        return edit_main(argv, sources)
    ap = argparse.ArgumentParser(
        prog="action-dag",
        description="Draw the action graph of a goal, with live status from GitLab MRs, "
        "ask-zk items and read-only probes.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""editing commands (`action-dag COMMAND --help` for the options):
  set  <goal> <node> [options]          change a node
  add  <goal> <node> --title T          add a node
  edge <goal> <A> <B> [--remove]        add or remove the edge [A, B]
  done <goal> <node> --label TEXT       move a finished node to the done row
  rm   <goal> <node> [--force]          remove a node

Each editing command keeps the comments and the layout of the YAML file. It
refuses to write a graph with errors. Then it writes the page again, as
--no-open does. --no-render stops this step. --dry-run prints a diff only.
The names set, add, edge, done and rm are reserved as the first argument.
To render a goal with one of these names, put `--` first: action-dag --no-open -- set

share the page:
  action-dag <goal> --public [--output FILE] [--redact-pattern REGEX ...]

Use --public for each page that leaves this machine (an Asana attachment,
Slack, email). The normal page contains the ask notes and local paths.""",
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
    ap.add_argument(
        "--public", action="store_true",
        help="write a page that is safe to share outside this machine: no ask data, no local "
        "paths, wiki links as their labels, no browser reload. Never reads or writes the state file",
    )
    ap.add_argument(
        "--output", metavar="FILE",
        help="with --public: the page to write (default <goal>.public.dag.html next to the YAML file)",
    )
    ap.add_argument(
        "--redact-pattern", action="append", default=[], metavar="REGEX",
        help="with --public: remove each match of REGEX from the text of the page "
        "(not from URLs). Give it more than once for more patterns",
    )
    args = ap.parse_args(argv)
    if not args.public and (args.output or args.redact_pattern):
        ap.error("--output and --redact-pattern need --public")
    if args.public and (args.watch is not None or args.json or args.check):
        ap.error("--public cannot go with --watch, --json or --check")
    patterns = []
    for rx in args.redact_pattern:
        try:
            patterns.append(re.compile(rx))
        except re.error as e:
            ap.error(f"--redact-pattern {rx!r} is not a valid regular expression: {e}")

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
    if args.public:
        output = Path(args.output).expanduser() if args.output else None
        return cmd_public(g, src, output, patterns)
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
