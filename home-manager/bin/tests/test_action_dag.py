#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["markdown-it-py>=3", "pytest>=8", "pyyaml>=6"]
# ///
"""Tests for ../action-dag.py.

Run: uv run --script home-manager/bin/tests/test_action_dag.py

The tests never call the real glab, ask-zk or gcloud. Two kinds of fake:
a Sources subclass with canned answers, and fake `glab` / `ask-zk`
executables on PATH that check their arguments.
"""

import importlib.util
import json
import os
import stat
import sys
from pathlib import Path

import pytest

sys.dont_write_bytecode = True  # keep __pycache__ out of home-manager/bin
HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("action_dag", HERE.parent / "action-dag.py")
ad = importlib.util.module_from_spec(SPEC)
sys.modules["action_dag"] = ad
SPEC.loader.exec_module(ad)

DEFAULTS = {"mr_host": "gitlab.example.com", "mr_project": "group/repo"}


def graph(nodes, edges, side=(), lanes=("l1", "l2"), done=()):
    data = {
        "goal": "t",
        "title": "Test",
        "defaults": DEFAULTS,
        "lanes": [{"id": x, "title": x} for x in lanes],
        "nodes": list(nodes),
        "side": list(side),
        "edges": [list(e) for e in edges],
        "done": list(done),
    }
    return ad.graph_from_dict(data, Path("/tmp/t.dag.yaml"))


def node(nid, status=None, lane="l1", **kw):
    d = {"id": nid, "lane": lane, "title": nid, "link": f"https://example.com/{nid}"}
    if status is not None:
        d["status"] = status
    d.update(kw)
    return d


class FakeSources(ad.Sources):
    def __init__(self, mrs=None, asks=None, probes=None, shows=None, notes=None):
        self.mrs = mrs or {}
        self.asks = asks or {}
        self.probes = probes or {}
        self.shows = shows or {}
        self.notes = notes or {}
        self.calls = []

    def fetch_ask_note(self, iid):
        if iid in self.notes:
            return f"/notebook/{iid}.md", self.notes[iid]
        return None

    def fetch_mr(self, mr):
        self.calls.append(("mr", mr["iid"]))
        v = self.mrs[mr["iid"]]
        if isinstance(v, Exception):
            raise v
        return v

    def fetch_asks(self):
        self.calls.append(("asks",))
        return self.asks

    def fetch_ask_show(self, iid):
        self.calls.append(("show", iid))
        if iid in self.shows:
            return self.shows[iid]
        raise RuntimeError("no such ask")

    def fetch_probe(self, cmd):
        self.calls.append(("probe", cmd))
        v = self.probes[cmd]
        if isinstance(v, Exception):
            raise v
        return v


def mr(state="opened", draft=False, approved=False, pipe="success"):
    return {
        "state": state,
        "draft": draft,
        "_approved": approved,
        "_approved_by": ["bob"] if approved else [],
        "head_pipeline": {"status": pipe},
    }


def run_derive(g, src):
    return ad.derive(g, ad.resolve_sources(g, src))


# ---------------------------------------------------------------- schema


def test_status_short_forms():
    g = graph(
        [
            node("A", "wait"),
            node("B", {"mr": 7}),
            node("C", [{"ask": "ab12"}, {"probe": "true", "pending": "wait"}]),
            node("D"),
        ],
        [],
    )
    assert g.nodes["A"].sources == [{"manual": "wait"}]
    assert g.nodes["B"].sources == [
        {"mr": {"host": "gitlab.example.com", "project": "group/repo", "iid": 7}}
    ]
    assert g.nodes["C"].sources == [{"ask": "ab12"}, {"probe": "true", "pending": "wait"}]
    assert g.nodes["D"].sources == [{"manual": "next"}]


def test_mr_link_is_derived():
    d = {"id": "B", "lane": "l1", "title": "B", "status": {"mr": 7}}
    g = graph([d], [])
    assert g.nodes["B"].link == "https://gitlab.example.com/group/repo/-/merge_requests/7"


def test_bad_status_source_is_an_error():
    with pytest.raises(ad.GraphError):
        graph([node("A", {"mr": 1, "ask": "x"})], [])
    with pytest.raises(ad.GraphError):
        graph([node("A", {"nonsense": 1})], [])


def test_duplicate_id_is_an_error():
    with pytest.raises(ad.GraphError):
        graph([node("A"), node("A")], [])


def test_check_reports_unknown_edge_ids_lanes_and_links():
    g = graph(
        [node("A"), node("B", lane="nope"), {"id": "C", "lane": "l1", "title": "C"}],
        [("A", "Z")],
    )
    errors, warnings = ad.check_graph(g)
    assert any("unknown node id 'Z'" in e for e in errors)
    assert any("lane 'nope'" in e for e in errors)
    assert any("node C: no link" in w for w in warnings)


def test_check_flags_a_probe_that_writes():
    g = graph([node("A", {"probe": "terragrunt apply -auto-approve"})], [])
    _, warnings = ad.check_graph(g)
    assert any("possibly writes" in w for w in warnings)
    g = graph([node("A", {"probe": "gcloud storage ls gs://b/ >/dev/null 2>&1"})], [])
    _, warnings = ad.check_graph(g)
    assert not any("possibly writes" in w for w in warnings)


def test_check_bad_manual_and_hold_until():
    g = graph([node("A", "soon", hold_until="Q")], [])
    errors, _ = ad.check_graph(g)
    assert any("manual 'soon'" in e for e in errors)
    assert any("hold_until 'Q'" in e for e in errors)


def test_check_accepts_the_seed_shape():
    g = graph([node("A"), node("B", lane="l2")], [("A", "B")], side=[{"id": "S", "title": "S", "link": "https://x"}])
    assert ad.check_graph(g) == ([], [])


# ---------------------------------------------------------------- cycles


def test_no_cycle():
    assert ad.find_cycle(["A", "B", "C"], [("A", "B"), ("B", "C"), ("A", "C")]) is None


def test_cycle_found():
    cyc = ad.find_cycle(["A", "B", "C"], [("A", "B"), ("B", "C"), ("C", "A")])
    assert cyc is not None and cyc[0] == cyc[-1] and set(cyc) == {"A", "B", "C"}


def test_self_loop_and_check_reports_cycle():
    assert ad.find_cycle(["A"], [("A", "A")]) == ["A", "A"]
    g = graph([node("A"), node("B")], [("A", "B"), ("B", "A")])
    errors, _ = ad.check_graph(g)
    assert any(e.startswith("cycle:") for e in errors)


# ---------------------------------------------------------------- derivation


def test_blocked_until_predecessors_done():
    g = graph([node("A", "next"), node("B", "next", lane="l2")], [("A", "B")])
    d = run_derive(g, FakeSources())
    assert d["A"].state == "next"
    assert d["B"].state == "blocked"
    assert "waits for A" in d["B"].detail


def test_done_node_stays_done_even_if_predecessor_open():
    g = graph([node("A", "next"), node("B", "done", lane="l2")], [("A", "B")])
    assert run_derive(g, FakeSources())["B"].state == "done"


def test_all_predecessors_done_gives_own_state():
    g = graph(
        [node("A", "done"), node("B", "done"), node("C", "decide", lane="l2")],
        [("A", "C"), ("B", "C")],
    )
    assert run_derive(g, FakeSources())["C"].state == "decide"


def test_mr_states():
    src = FakeSources(
        mrs={
            1: mr(state="merged"),
            2: mr(draft=True),
            3: mr(),
            4: mr(approved=True),
            5: mr(pipe="failed"),
            6: mr(state="closed"),
        }
    )
    g = graph([node(f"M{i}", {"mr": i}) for i in range(1, 7)], [])
    d = run_derive(g, src)
    assert [d[f"M{i}"].state for i in range(1, 7)] == ["done", "wait", "wait", "next", "next", "unknown"]
    assert d["M2"].pill == "Draft"
    assert d["M3"].pill == "Review"
    assert d["M4"].pill == "Merge"
    assert d["M6"].warn


def test_ask_states_and_stale_warning():
    src = FakeSources(
        asks={
            "a1": {"state": "open", "age_days": 1, "what": ""},
            "a2": {"state": "done", "age_days": 30, "what": ""},
            "a3": {"state": "open", "age_days": 30, "what": ""},
            "a4": {"state": "drop", "age_days": 2, "what": ""},
        }
    )
    g = graph([node(f"N{i}", {"ask": f"a{i}"}) for i in range(1, 5)], [])
    d = run_derive(g, src)
    assert d["N1"].state == "next" and not d["N1"].warn
    assert d["N2"].state == "done"
    assert d["N3"].state == "next" and any("stale" in w for w in d["N3"].warn)
    assert d["N4"].state == "unknown"


def test_legacy_ask_id_falls_back_to_show():
    src = FakeSources(asks={}, shows={"78b527b9": {"state": "done", "age_days": 0, "what": ""}})
    g = graph([node("A", {"ask": "78b527b9"})], [])
    assert run_derive(g, src)["A"].state == "done"
    assert ("show", "78b527b9") in src.calls


def test_probe_pass_fail_timeout():
    src = FakeSources(probes={"ok": 0, "no": 1, "slow": TimeoutError("probe timed out after 8 s")})
    g = graph(
        [node("P1", {"probe": "ok"}), node("P2", {"probe": "no", "pending": "wait"}), node("P3", {"probe": "slow"})],
        [],
    )
    d = run_derive(g, src)
    assert d["P1"].state == "done"
    assert d["P2"].state == "wait"
    assert d["P3"].state == "unknown" and "timed out" in d["P3"].detail


def test_any_done_source_makes_the_node_done_and_flags_the_open_ask():
    src = FakeSources(asks={"a1": {"state": "open", "age_days": 0, "what": ""}}, probes={"ok": 0})
    g = graph([node("A", [{"ask": "a1"}, {"probe": "ok"}])], [])
    d = run_derive(g, src)
    assert d["A"].state == "done"
    assert any("tick the ask" in w for w in d["A"].warn)


def test_lookup_failure_is_unknown_not_a_crash():
    src = FakeSources(mrs={9: RuntimeError("glab api: 401 Unauthorized")})
    g = graph([node("A", {"mr": 9}), node("B", "next", lane="l2")], [("A", "B")])
    d = run_derive(g, src)
    assert d["A"].state == "unknown" and "401" in d["A"].detail
    assert d["B"].state == "blocked"


def test_hold_until_warns_when_mr_out_of_draft_or_approved():
    src = FakeSources(mrs={10: mr(), 11: mr(draft=True), 12: mr(draft=True, approved=True), 13: mr(state="merged")})
    g = graph(
        [
            node("C3", "next"),
            node("K1", {"mr": 10}, lane="l2", hold_until="C3"),
            node("K2", {"mr": 11}, lane="l2", hold_until="C3"),
            node("K3", {"mr": 12}, lane="l2", hold_until="C3"),
            node("K4", {"mr": 13}, lane="l2", hold_until="C3"),
        ],
        [("C3", "K1"), ("C3", "K2"), ("C3", "K3"), ("C3", "K4")],
    )
    d = run_derive(g, src)
    assert any("out of draft" in w for w in d["K1"].warn)
    assert not d["K2"].warn
    assert any("approved" in w for w in d["K3"].warn)
    assert any("merged before C3" in w for w in d["K4"].warn)


def test_hold_until_quiet_once_hold_node_done():
    src = FakeSources(mrs={10: mr()})
    g = graph([node("C3", "done"), node("K1", {"mr": 10}, lane="l2", hold_until="C3")], [("C3", "K1")])
    assert not run_derive(g, src)["K1"].warn


def test_owner_name_on_manual_wait_pill():
    g = graph([node("F", "wait", owner="Alex")], [])
    assert run_derive(g, FakeSources())["F"].pill == "Alex"


# ---------------------------------------------------------------- state file and output


def test_changes_since_last_run():
    last = {"nodes": {"A": {"state": "next"}, "B": {"state": "wait"}}}
    derived = {
        "A": ad.Derived("done", "Done", "", [], "done"),
        "B": ad.Derived("wait", "Review", "", [], "wait"),
        "C": ad.Derived("next", "Next", "", [], "next"),
    }
    assert ad.changes(last, derived) == {"A": "next"}


def test_main_end_to_end(tmp_path, capsys, monkeypatch):
    yml = tmp_path / "g.dag.yaml"
    yml.write_text(
        json.dumps(
            {
                "goal": "g",
                "title": "G <map>",
                "defaults": DEFAULTS,
                "lanes": [{"id": "l1", "title": "One"}, {"id": "l2", "title": "Two", "align": "center"}],
                "nodes": [node("A", {"ask": "a1"}), node("B", {"mr": 5}, lane="l2", hold_until="A")],
                "edges": [["A", "B"]],
                "done": [{"label": "old", "link": "https://example.com/old"}],
                "side": [{"id": "S", "title": "Side", "link": "https://example.com/s", "status": "wait"}],
            }
        )
    )
    src = FakeSources(asks={"a1": {"state": "open", "age_days": 0, "what": ""}}, mrs={5: mr()})
    assert ad.main([str(yml), "--no-open"], sources=src) == 0
    out = capsys.readouterr().out
    assert "Next for you:" in out and "A  A" in out and "ask a1" in out
    assert "!5 is out of draft. Do not merge before A." in out
    assert "first run" in out
    page = (tmp_path / "g.dag.html").read_text()
    assert "G &lt;map&gt;" in page and "{{" not in page
    assert 'id="n-A"' in page and '[["n-A", "n-B"]]' in page
    state = json.loads((tmp_path / "g.dag.state.json").read_text())
    assert state["nodes"]["A"]["state"] == "next"

    # Second run: A is now done, so it is marked as changed.
    src.asks["a1"]["state"] = "done"
    assert ad.main([str(yml), "--no-open"], sources=src) == 0
    out = capsys.readouterr().out
    assert "A: next -> done" in out
    assert "was next" in (tmp_path / "g.dag.html").read_text()


def test_main_refuses_an_invalid_graph(tmp_path, capsys):
    yml = tmp_path / "bad.dag.yaml"
    yml.write_text(json.dumps({"lanes": ["l1"], "nodes": [node("A")], "edges": [["A", "Q"]]}))
    assert ad.main([str(yml), "--check"]) == 1
    assert "unknown node id 'Q'" in capsys.readouterr().out
    assert ad.main([str(yml), "--no-open"], sources=FakeSources()) == 2
    assert not (tmp_path / "bad.dag.html").exists()


# ---------------------------------------------------------------- fake executables


def write_exe(path: Path, body: str) -> None:
    path.write_text("#!/bin/sh\n" + body)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def test_real_sources_with_fake_glab_and_ask_zk(tmp_path, monkeypatch):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    log = tmp_path / "calls.log"
    # ask-zk: refuse to run without --no-verify (the list verb would close items).
    write_exe(
        bindir / "ask-zk",
        f'echo "$@" >> {log}\n'
        'case " $* " in *" --no-verify "*) ;; *) echo "probes ran" >&2; exit 9;; esac\n'
        'case "$*" in\n'
        '  *" list --all") printf "ab12\\t3d\\topen\\tDo a thing\\ncd34\\t12d\\tdone\\tOld\\n";;\n'
        '  *" show 1234abcd") printf -- "---\\nask_id: 1234abcd\\nclosed: drop\\n---\\n\\n- [x] x  #ask\\n";;\n'
        "  *) exit 1;;\n"
        "esac\n",
    )
    write_exe(
        bindir / "glab",
        f'echo "$@" >> {log}\n'
        'case "$*" in\n'
        '  *"/approvals") echo \'{"approved": true, "approved_by": [{"user": {"username": "bob"}}]}\';;\n'
        "  *) echo '{\"state\": \"opened\", \"draft\": false, \"head_pipeline\": {\"status\": \"success\"}}';;\n"
        "esac\n",
    )
    monkeypatch.setenv("PATH", f"{bindir}{os.pathsep}{os.environ['PATH']}")
    src = ad.Sources()
    monkeypatch.setattr(ad, "NOTEBOOK", tmp_path)
    (tmp_path / "ab12.md").write_text("# hi\n")
    assert src.fetch_ask_note("ab12") == (str(tmp_path / "ab12.md"), "# hi\n")
    assert src.fetch_ask_note("nope") is None
    asks = src.fetch_asks()
    assert asks["ab12"] == {"state": "open", "age_days": 3, "what": "Do a thing"}
    assert asks["cd34"]["state"] == "done"
    assert src.fetch_ask_show("1234abcd")["state"] == "drop"
    data = src.fetch_mr({"host": "gitlab.example.com", "project": "group/sub repo", "iid": 3})
    assert data["_approved"] and data["_approved_by"] == ["bob"]
    calls = log.read_text()
    assert "--hostname gitlab.example.com projects/group%2Fsub%20repo/merge_requests/3" in calls
    assert "probes ran" not in calls
    assert src.fetch_probe("exit 0")["rc"] == 0
    failed = src.fetch_probe("echo 'boom glpat-abcdefghij1234567890' >&2; exit 4")
    assert failed["rc"] == 4 and "boom [REDACTED]" in failed["stderr"]


# ---------------------------------------------------------------- markdown, redaction, panel

ASK_NOTE = """---
created: 2026-10-08T17:18:47Z
by: someone
---

# Apply the unit <b>now</b>

- [ ] Apply the unit  #ask #frmod

## Why

The planner cannot read the project. <script>alert(1)</script>

## Do this

```fish
set -gx TOKEN glpat-AAAABBBBCCCCDDDDEEEE
xh -I GET https://example.com Authorization:"Bearer abcdefghijklmnopqrstuvwxyz0123456789"
terragrunt apply
```

## Done when

[evil](javascript:alert(1)) and [ok](https://example.com/x)
"""


def test_redact_known_token_shapes():
    text = (
        "a glpat-abcdefghij1234 b gldt-ZZZZYYYYXXXX1234 c gloas-0123456789abcdef "
        "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig d ghp_abcdefghijklmnopqrstuvwxyz012345"
    )
    out = ad.redact(text)
    for secret in ("glpat-abc", "gldt-ZZZ", "gloas-012", "eyJhbGci", "ghp_abc"):
        assert secret not in out
    assert "Bearer [REDACTED]" in out
    assert ad.redact("plain text, no token: gs://bucket/terragrunt/") == "plain text, no token: gs://bucket/terragrunt/"


def test_redact_upper_case_variable_but_not_a_secret_name_flag():
    flag = "gcloud secrets versions access latest --secret=chronosphere-api-token-frmod --project=p"
    assert ad.redact(flag) == flag
    assert ad.redact("--secret=foo") == "--secret=foo"
    assert ad.redact("GITLAB_TOKEN=abc123def456ghi789jkl") == "GITLAB_TOKEN=[REDACTED]"
    assert ad.redact("export API_SECRET='abcdefghijklmnop1234'") == "export API_SECRET='[REDACTED]'"
    assert ad.redact("password=abcdefghijklmnop1234") == "password=abcdefghijklmnop1234"


def test_md_to_html_escapes_html_adds_copy_and_redacts():
    meta, body = ad.split_frontmatter(ASK_NOTE)
    assert meta["created"] == "2026-10-08T17:18:47Z"
    assert not body.startswith("---")
    out = ad.md_to_html(body)
    assert "<script>" not in out and "&lt;script&gt;" in out
    assert "<b>now</b>" not in out
    assert '<h2>Do this</h2>' in out
    assert '<div class="code"><span class="lang">fish</span><button type="button" class="copy">Copy</button><pre><code' in out
    assert out.count('class="copy"') == 1 and out.count("</code></pre></div>") == 1
    assert "glpat-AAAA" not in out and "abcdefghijklmnop" not in out
    assert "href=\"javascript:" not in out  # left as plain text, never a link
    assert 'href="https://example.com/x"' in out


def test_panel_shows_ask_note_mr_facts_probe_and_chips(tmp_path):
    g = graph(
        [
            node("A", {"ask": "ab12"}),
            node("B", {"mr": 5}, hold_until="A", links=[{"label": "Open runbook", "url": "https://example.com/rb"}]),
            node("P", {"probe": "false"}),
            node("C", "decide", lane="l2", notes="Choose **one**:\n\n- keep\n- drop"),
        ],
        [("A", "C"), ("B", "C"), ("P", "C")],
    )
    pipe = mr()
    pipe["web_url"] = "https://gitlab.example.com/group/repo/-/merge_requests/5"
    pipe["title"] = "Switch backend"
    pipe["head_pipeline"]["web_url"] = "https://gitlab.example.com/group/repo/-/pipelines/9"
    src = FakeSources(
        asks={"ab12": {"state": "open", "age_days": 2, "what": ""}},
        notes={"ab12": ASK_NOTE},
        mrs={5: pipe},
        probes={"false": {"rc": 1, "stderr": "ERROR: matched no objects"}},
    )
    d = run_derive(g, src)
    page = ad.render(g, d, {}, "2026-10-12 12:00:00 UTC", ad.TEMPLATE.read_text())
    assert '<template id="p-A">' in page and "Ask ab12" in page and "<h2>Why</h2>" in page
    assert "/notebook/ab12.md" in page and "2026-10-08T17:18:47Z" in page
    assert ">Open MR</a>" in page and "pipelines/9" in page and "Switch backend" in page
    assert ">Open runbook</a>" in page
    assert "Probe (read-only)" in page and "exit 1" in page and "matched no objects" in page
    assert "<strong>one</strong>" in page
    assert 'data-goto="A"' in page and 'data-goto="C"' in page
    assert "glpat-AAAA" not in page and "<script>alert" not in page
    assert '<button type="button" class="node' in page and '<a class="node' not in page
    assert '<noscript><meta http-equiv="refresh" content="60"></noscript>' in page
    assert "const RELOAD = 60;" in page and "location.reload()" in page
    assert "Generated <b>2026-10-12 12:00:00 UTC</b>" in page


def test_output_path_refresh_and_open_only_when_new(tmp_path, monkeypatch, capsys):
    yml = tmp_path / "g.dag.yaml"
    yml.write_text(json.dumps({
        "goal": "g", "lanes": ["l1"], "output": "custom-page.html", "refresh_seconds": 0,
        "nodes": [node("A", "next")],
    }))
    opened = []
    monkeypatch.setattr(ad, "open_page", lambda p: opened.append(p))
    assert ad.main([str(yml)], sources=FakeSources()) == 0
    page = tmp_path / "custom-page.html"
    assert page.exists() and not (tmp_path / "g.dag.html").exists()
    assert "http-equiv" not in page.read_text() and "const RELOAD = 0;" in page.read_text()
    assert (tmp_path / "g.dag.state.json").exists()
    assert opened == [page]
    assert ad.main([str(yml)], sources=FakeSources()) == 0
    assert opened == [page]  # the file was already there: no second tab
    assert not list(tmp_path.glob(".*.tmp"))  # atomic write left no temp file


def test_check_rejects_output_that_is_not_html(tmp_path):
    g = ad.graph_from_dict({"lanes": ["l1"], "nodes": [node("A")], "output": "g.dag.yaml"}, tmp_path / "g.dag.yaml")
    errors, _ = ad.check_graph(g)
    assert any("output must be an .html file" in e for e in errors)


def test_one_line_summary():
    g = graph([node("A", "next"), node("B", "done")], [])
    d = run_derive(g, FakeSources())
    line = ad.one_line(g, d, {"A": "wait"}, "T")
    assert line == "T  t: next=1 done=1 warnings=0 changed=1"


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q", "-p", "no:cacheprovider"]))
