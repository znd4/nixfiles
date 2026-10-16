#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["markdown-it-py>=3", "pytest>=8", "pyyaml>=6", "ruamel.yaml>=0.19,<0.20"]
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
        "nodes": list(nodes),
        "side": list(side),
        "edges": [list(e) for e in edges],
        "done": list(done),
    }
    if lanes is not None:  # None: a graph with no `lanes:` key
        data["lanes"] = [{"id": x, "title": x} for x in lanes]
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


def mr(state="opened", draft=False, approved=False, pipe="success", conflicts=False, merge_status=""):
    return {
        "state": state,
        "draft": draft,
        "_approved": approved,
        "_approved_by": ["bob"] if approved else [],
        "head_pipeline": {"status": pipe},
        "has_conflicts": conflicts,
        "detailed_merge_status": merge_status,
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


def test_mr_conflicts_rebase_and_threads():
    src = FakeSources(mrs={
        1: mr(conflicts=True, approved=True),
        2: mr(merge_status="need_rebase"),
        3: mr(merge_status="discussions_not_resolved"),
        4: mr(draft=True, conflicts=True),
        5: mr(merge_status="conflict"),
        6: mr(approved=True),
    })
    g = graph([node(f"M{i}", {"mr": i}) for i in range(1, 7)], [])
    d = run_derive(g, src)
    assert (d["M1"].state, d["M1"].pill) == ("next", "Conflicts")
    assert (d["M2"].state, d["M2"].pill) == ("next", "Rebase")
    assert (d["M3"].state, d["M3"].pill) == ("next", "Threads")
    assert (d["M4"].state, d["M4"].pill) == ("wait", "Draft")
    assert any("merge conflicts" in w for w in d["M4"].warn)
    assert (d["M5"].state, d["M5"].pill) == ("next", "Conflicts")
    assert (d["M6"].state, d["M6"].pill) == ("next", "Merge")


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


# ---------------------------------------------------------------- board columns


def cols(g, src=None):
    """[(title, [ids])] of the board, from left to right."""
    return [(c.title, c.ids) for c in ad.board_columns(g, run_derive(g, src or FakeSources()))]


def page_cols(page):
    """[(data-col, [card ids])] from a rendered page."""
    import re

    out = []
    for key, body in re.findall(r'<section class="col [^"]*" data-col="([^"]+)">(.*?)</section>', page, re.S):
        out.append((key, re.findall(r'data-node="([^"]+)"', body)))
    return out


def test_finished_predecessor_moves_its_successor_to_ready_now():
    # The reported bug: S0 is done, so S1 is ready, whatever their YAML lanes say.
    g = graph([node("S0", "done"), node("S1", "next", lane="l2"), node("S2", "next", lane="l2")],
              [("S0", "S1"), ("S1", "S2")])
    assert cols(g) == [("Done", ["S0"]), ("Ready now", ["S1"]), ("After 1 step", ["S2"])]


def test_open_chain_gives_one_column_per_step():
    g = graph([node("A"), node("B"), node("C")], [("A", "B"), ("B", "C")])
    assert cols(g) == [("Ready now", ["A"]), ("After 1 step", ["B"]), ("After 2 steps", ["C"])]
    assert [c.sub for c in ad.board_columns(g, run_derive(g, FakeSources()))] == [
        "No open step before it", "Waits for open steps", "Waits for open steps",
    ]


def test_column_follows_the_longest_open_chain_and_ignores_done_predecessors():
    # D has a done predecessor (A) and an open one (C, after B): it goes by C.
    # E comes after a done node only: it is ready.
    g = graph(
        [node("A", "done"), node("B"), node("C"), node("D"), node("E")],
        [("A", "D"), ("B", "C"), ("C", "D"), ("A", "E")],
    )
    assert cols(g) == [
        ("Done", ["A"]), ("Ready now", ["B", "E"]), ("After 1 step", ["C"]), ("After 2 steps", ["D"]),
    ]
    # An open node behind a done node behind an open node: the done node stops the chain.
    g = graph([node("X"), node("Y", "done"), node("Z")], [("X", "Y"), ("Y", "Z")])
    assert cols(g) == [("Done", ["Y"]), ("Ready now", ["X", "Z"])]


def test_empty_columns_are_not_shown():
    g = graph([node("A"), node("B", "wait")], [])
    assert cols(g) == [("Ready now", ["A", "B"])]
    g = graph([node("A", "done")], [])
    assert cols(g) == [("Done", ["A"])]
    # Only a side track is between A and B, so "After 1 step" has no card.
    g = graph([node("A"), node("B")], [("A", "S"), ("S", "B")], side=[node("S")])
    assert cols(g) == [("Ready now", ["A"]), ("After 2 steps", ["B"])]
    page = ad.render(g, run_derive(g, FakeSources()), {}, "T", ad.TEMPLATE.read_text())
    assert "repeat(2, minmax" in page
    assert page_cols(page) == [("ready", ["A"]), ("after-2", ["B"])]


def test_graph_without_lanes_checks_renders_and_edits(tmp_path, capsys):
    yml = tmp_path / "nl.dag.yaml"
    yml.write_text(json.dumps({
        "goal": "nl", "defaults": DEFAULTS,
        "nodes": [
            {"id": "A", "title": "A", "link": "https://example.com/a", "status": "done"},
            {"id": "B", "title": "B", "link": "https://example.com/b"},
        ],
        "edges": [["A", "B"]],
    }))
    assert ad.main([str(yml), "--check"]) == 0
    assert "0 errors, 0 warnings" in capsys.readouterr().out
    assert ad.main([str(yml), "--no-open"], sources=FakeSources()) == 0
    page = (tmp_path / "nl.dag.html").read_text()
    assert page_cols(page) == [("done", ["A"]), ("ready", ["B"])]
    assert "repeat(2, minmax" in page and "Lane:" not in page
    assert ad.main(["add", str(yml), "C", "--title", "C", "--after", "B", "--no-render"]) == 0
    assert ad.load_graph(yml).nodes["C"].lane is None
    assert ad.main([str(yml), "--no-open"], sources=FakeSources()) == 0
    assert page_cols((tmp_path / "nl.dag.html").read_text())[-1] == ("after-1", ["C"])


def test_old_graph_with_lanes_renders_and_shows_the_lane_in_the_panel():
    g = graph(
        [node("A", "done", lane="l2"), node("B", lane="l1"), node("C", lane="l1")],
        [("A", "B"), ("B", "C")],
        lanes=("l1", "l2"),
    )
    g.lanes[1]["title"] = "Lane <two>"
    assert ad.check_graph(g) == ([], [])
    page = ad.render(g, run_derive(g, FakeSources()), {}, "T", ad.TEMPLATE.read_text())
    assert page_cols(page) == [("done", ["A"]), ("ready", ["B"]), ("after-1", ["C"])]
    assert '<p class="laneline">Lane: Lane &lt;two&gt;</p>' in page
    assert '<p class="laneline">Lane: l1</p>' in page
    assert '<h2>Done<small>Finished steps</small></h2>' in page
    # The id row of a card does not change.
    assert '<span class="id">A</span>' in page


def test_lane_is_optional_but_must_be_known_when_lanes_are_given():
    g = graph([{"id": "A", "title": "A", "link": "https://example.com/a"}], [])
    assert ad.check_graph(g) == ([], [])
    g = graph([node("A", lane="free text")], [], lanes=None)
    assert ad.check_graph(g) == ([], [])
    g = graph([node("A", lane="nope")], [])
    assert any("lane 'nope' is not in `lanes`" in e for e in ad.check_graph(g)[0])


def test_done_card_with_an_open_predecessor_stays_in_done():
    g = graph([node("A"), node("B", "done")], [("A", "B")])
    assert cols(g) == [("Done", ["B"]), ("Ready now", ["A"])]


def test_same_input_gives_the_same_page():
    g = graph([node("A", "done"), node("B"), node("C"), node("D")], [("A", "C"), ("B", "C"), ("C", "D")])
    first = ad.render(g, run_derive(g, FakeSources()), {}, "T", ad.TEMPLATE.read_text())
    second = ad.render(g, run_derive(g, FakeSources()), {}, "T", ad.TEMPLATE.read_text())
    assert first == second
    assert page_cols(first) == [("done", ["A"]), ("ready", ["B"]), ("after-1", ["C"]), ("after-2", ["D"])]


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
    # The page has the chain view. The outline class is not .rel, because .rel
    # is the panel's "Waits on" / "Unblocks" grid.
    assert "function chain(" in page and "drawChain()" in page
    assert "button.node.linked" in page and 'classList.add("rel")' not in page
    assert "Generated <b>2026-10-12 12:00:00 UTC</b>" in page


def test_panel_mr_buttons_come_first():
    g = graph([node("A", {"mr": 5}, link="https://example.com/doc", links=[{"label": "Open runbook", "url": "https://example.com/rb"}])], [])
    pipe = {"state": "opened", "draft": False, "approved": False, "web_url": "https://gitlab.example.com/group/repo/-/merge_requests/5",
            "head_pipeline": {"status": "success", "web_url": "https://gitlab.example.com/group/repo/-/pipelines/9"}, "title": "A"}
    page = ad.render(g, run_derive(g, FakeSources(mrs={5: pipe})), {}, "now", ad.TEMPLATE.read_text())
    tpl = page[page.index('<template id="p-A">'):]
    btns = tpl[tpl.index('<div class="btns">'):tpl.index("</div>", tpl.index('<div class="btns">'))]
    order = [btns.index(x) for x in (">Open MR !5<", ">Open pipeline<", "example.com/doc", ">Open runbook<")]
    assert order == sorted(order)


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


# ---------------------------------------------------------------- editing commands

FX = """\
# Top comment: the fixture graph.
goal: fx
title: "Fixture: quoted title"
defaults:
  mr_host: gitlab.example.com
  mr_project: group/repo

lanes:
  - {id: l1, title: "Lane one"}   # first lane
  - {id: l2, title: 'Lane two'}

nodes:
  # --- lane one ---
  - id: A
    lane: l1
    title: "First step"
    link: https://example.com/a
    status: {manual: done}
    notes: |
      Line one.
      Line two.

  - id: B
    lane: l1
    title: 'Second: step'  # trailing comment
    link: https://example.com/b
    status:
      - ask: ab12
      - probe: "test -e /tmp/x"
        pending: wait
    asks: [cd34]

  # --- lane two ---
  - id: C
    lane: l2
    title: Third step
    link: https://example.com/c
    status: {mr: 7}
    hold_until: A
edges:
  - [A, B]   # A before B
  - [B, C]

done:
  - {label: "old", link: "https://example.com/old"}
"""
B_BLOCK = FX[FX.index("  - id: B\n"):FX.index("\n  # --- lane two ---")]


@pytest.fixture
def fx(tmp_path, monkeypatch):
    """The fixture graph, and a counter of page renders (the real render is
    replaced, so no test calls glab or ask-zk by accident)."""
    path = tmp_path / "fx.dag.yaml"
    path.write_text(FX)
    renders = []
    monkeypatch.setattr(ad, "render_page", lambda p, src: renders.append(p))
    monkeypatch.setattr(ad, "open_page", lambda p: pytest.fail("an edit opened a browser tab"))
    return path, renders


def edit(path, *args, src=None):
    cmd, rest = args[0], list(args[1:])
    return ad.main([cmd, str(path), *rest], sources=src or FakeSources())


def test_round_trip_without_an_edit_gives_the_same_bytes(fx):
    doc = ad.load_doc(fx[0])
    assert doc.exact and doc.dump() == FX


def test_set_changes_only_the_node(fx):
    path, renders = fx
    assert edit(path, "set", "B", "--title", "New title", "--sub", "a sub", "--add-ask", "ef56") == 0
    text = path.read_text()
    head, tail = FX.split(B_BLOCK)
    assert text.startswith(head) and text.endswith(tail)
    block = text[len(head):len(text) - len(tail)]
    assert block == (
        "  - id: B\n"
        "    lane: l1\n"
        "    title: 'New title'     # trailing comment\n"
        "    sub: a sub\n"
        "    link: https://example.com/b\n"
        "    status:\n"
        "      - ask: ab12\n"
        '      - probe: "test -e /tmp/x"\n'
        "        pending: wait\n"
        "    asks: [cd34, ef56]\n"
    )
    assert renders == [path]


def test_set_state_status_list_and_safe_quoting(fx):
    path, _ = fx
    assert edit(
        path, "set", "C", "--title", "yes", "--add-ask", "0123",
        "--status", "ask:ff00", "--status", "probe:test -e /tmp/y", "--pending", "wait",
    ) == 0
    g = ad.load_graph(path)  # PyYAML reads it, as the render does
    c = g.nodes["C"]
    assert c.title == "yes" and c.asks == ["0123"]
    assert c.sources == [{"ask": "ff00"}, {"probe": "test -e /tmp/y", "pending": "wait"}]
    assert edit(path, "set", "C", "--state", "decide") == 0
    assert "    status: {manual: decide}\n" in path.read_text()
    assert edit(path, "set", "C", "--status", "mr:group/other!12") == 0
    assert "    status: {mr: {project: group/other, iid: 12}}\n" in path.read_text()
    assert edit(path, "set", "C", "--status", "mr:https://gitlab.example.com/group/repo/-/merge_requests/9") == 0
    assert "    status: {mr: 9}\n" in path.read_text()


def test_set_state_and_status_together_is_refused(fx, capsys):
    path, renders = fx
    assert edit(path, "set", "C", "--state", "done", "--status", "ask:x") == 1
    assert path.read_text() == FX and not renders
    assert "not both" in capsys.readouterr().err


def test_notes_append_replace_and_remove_keep_the_blank_line(fx):
    path, _ = fx
    assert edit(path, "set", "A", "--append-note", "Line three.") == 0
    text = path.read_text()
    assert "    notes: |\n      Line one.\n      Line two.\n      Line three.\n\n  - id: B\n" in text
    assert edit(path, "set", "A", "--note", "One line") == 0
    assert "    notes: One line\n\n  - id: B\n" in path.read_text()
    assert edit(path, "set", "A", "--note", "") == 0
    assert "    status: {manual: done}\n\n  - id: B\n" in path.read_text()
    # A new key after the last key also takes the blank line.
    assert edit(path, "set", "A", "--tag", "runbook 1") == 0
    assert "    tag: runbook 1\n\n  - id: B\n" in path.read_text()
    assert edit(path, "set", "C", "--append-note", "First note.") == 0
    assert "    hold_until: A\n    notes: First note.\nedges:\n" in path.read_text()


def test_remove_ask_and_empty_value_removes_the_key(fx, capsys):
    path, _ = fx
    assert edit(path, "set", "B", "--remove-ask", "zz") == 1
    assert "ask zz is not in asks" in capsys.readouterr().err
    assert path.read_text() == FX
    assert edit(path, "set", "B", "--remove-ask", "cd34") == 0
    assert "asks:" not in path.read_text()
    assert edit(path, "set", "C", "--hold-until", "") == 0
    assert "hold_until" not in path.read_text()


def test_set_unknown_node_and_unknown_lane_are_refused(fx, capsys):
    path, renders = fx
    assert edit(path, "set", "Q", "--title", "x") == 1
    assert edit(path, "set", "B", "--lane", "nope") == 1
    assert "lane 'nope' is not in `lanes`" in capsys.readouterr().err
    assert path.read_text() == FX and not renders


def test_set_probe_that_writes_gives_the_warning(fx, capsys):
    path, _ = fx
    assert edit(path, "set", "C", "--status", "probe:kubectl apply -f x.yaml") == 0
    assert "possibly writes" in capsys.readouterr().err


def test_no_change_writes_nothing(fx, capsys):
    path, renders = fx
    before = path.stat().st_mtime_ns
    assert edit(path, "set", "B", "--title", "Second: step") == 0
    assert "no change" in capsys.readouterr().out
    assert path.stat().st_mtime_ns == before and not renders


def test_add_puts_the_node_after_its_lane_and_adds_edges(fx):
    path, _ = fx
    assert edit(
        path, "add", "X", "--lane", "l1", "--title", "New step",
        "--link", "https://example.com/x", "--after", "A", "--before", "C",
    ) == 0
    text = path.read_text()
    assert (
        "    asks: [cd34]\n"
        "  - id: X\n"
        "    lane: l1\n"
        "    title: New step\n"
        "    link: https://example.com/x\n"
        "    status: {manual: next}\n"
        "\n"
        "  # --- lane two ---\n"
    ) in text
    assert "  - [B, C]\n  - [A, X]\n  - [X, C]\n\ndone:\n" in text
    assert ad.cmd_check(path) == 0


def test_add_side_node_and_refusals(fx, capsys):
    path, _ = fx
    assert edit(path, "add", "B", "--lane", "l1", "--title", "dup") == 1
    assert edit(path, "add", "Y", "--lane", "l1") == 1  # no title
    assert edit(path, "add", "Y", "--side", "--lane", "l1", "--title", "Y") == 1
    assert edit(path, "add", "Y", "--lane", "nope", "--title", "Y") == 1
    assert path.read_text() == FX
    assert edit(path, "add", "S1", "--side", "--title", "Side", "--status", "ask:ab99") == 0
    text = path.read_text()
    assert text.endswith("side:\n  - id: S1\n    title: Side\n    status: {ask: ab99}\n")
    assert ad.load_graph(path).nodes["S1"].side


def test_add_and_set_without_a_lane(fx, capsys):
    path, _ = fx
    assert edit(path, "add", "Y", "--title", "No lane", "--link", "https://example.com/y", "--after", "C") == 0
    assert "add Y, edges [C, Y]" in capsys.readouterr().out
    text = path.read_text()
    assert "    hold_until: A\n  - id: Y\n    title: No lane\n" in text
    assert edit(path, "set", "B", "--lane", "") == 0
    g = ad.load_graph(path)
    assert g.nodes["Y"].lane is None and g.nodes["B"].lane is None
    assert ad.cmd_check(path) == 0


def test_edge_add_remove_and_cycle_refused(fx, capsys):
    path, renders = fx
    assert edit(path, "edge", "C", "A") == 1
    assert "cycle" in capsys.readouterr().err
    assert path.read_text() == FX and not renders
    assert edit(path, "edge", "A", "B") == 1  # already there
    assert edit(path, "edge", "A", "C") == 0
    assert "  - [B, C]\n  - [A, C]\n\ndone:\n" in path.read_text()
    assert edit(path, "edge", "A", "B", "--remove") == 0
    text = path.read_text()
    assert "[A, B]" not in text and "# A before B" not in text
    assert edit(path, "edge", "Q", "R", "--remove") == 1


def test_done_moves_the_node_and_bridges_its_edges(fx):
    path, _ = fx
    src = FakeSources(asks={"ab12": {"state": "done", "age_days": 0, "what": ""}}, probes={"test -e /tmp/x": 1})
    assert edit(path, "done", "B", "--label", "B finished", src=src) == 0
    text = path.read_text()
    assert "id: B" not in text
    # One blank line between A and the lane heading, not two.
    assert "      Line two.\n\n  # --- lane two ---\n  - id: C\n" in text
    assert "edges:\n  - [A, C]\n\ndone:\n" in text
    assert text.endswith(
        '  - {label: "old", link: "https://example.com/old"}\n'
        '  - {label: "B finished", link: "https://example.com/b"}\n'
    )
    assert ad.cmd_check(path) == 0


def test_done_refuses_a_node_that_is_not_done(fx, capsys):
    path, renders = fx
    src = FakeSources(asks={"ab12": {"state": "open", "age_days": 0, "what": ""}}, probes={"test -e /tmp/x": 1})
    assert edit(path, "done", "B", "--label", "B", src=src) == 1
    assert "is next" in capsys.readouterr().err
    assert path.read_text() == FX and not renders
    assert edit(path, "done", "B", "--label", "B", "--force", "--link", "https://example.com/z", src=src) == 0
    assert '{label: "B", link: "https://example.com/z"}' in path.read_text()


def test_done_removes_hold_until_on_the_node(fx):
    path, _ = fx
    assert edit(path, "done", "A", "--label", "A finished") == 0  # manual: done
    text = path.read_text()
    assert "hold_until" not in text and "[A, B]" not in text
    assert "nodes:\n  # --- lane one ---\n  - id: B\n" in text
    assert ad.cmd_check(path) == 0


def test_rm_refuses_while_used_then_force_removes_the_references(fx, capsys):
    path, renders = fx
    assert edit(path, "rm", "A") == 1
    err = capsys.readouterr().err
    assert "edges [A, B]" in err and "hold_until of C" in err
    assert path.read_text() == FX and not renders
    assert edit(path, "rm", "A", "--force") == 0
    text = path.read_text()
    assert "id: A" not in text and "[A, B]" not in text and "hold_until" not in text
    assert ad.cmd_check(path) == 0


def test_dry_run_prints_a_diff_and_writes_nothing(fx, capsys):
    path, renders = fx
    assert edit(path, "set", "B", "--sub", "planned", "--dry-run") == 0
    out = capsys.readouterr().out
    assert f"--- {path}" in out and "+    sub: planned\n" in out
    assert "dry run, nothing written: fx.dag.yaml: set B: sub 'planned' (+1 -0 lines)" in out
    assert path.read_text() == FX and not renders


def test_render_once_after_an_edit_but_not_with_no_render(fx):
    path, renders = fx
    assert edit(path, "set", "B", "--sub", "one") == 0
    assert renders == [path]
    assert edit(path, "set", "B", "--sub", "two", "--no-render") == 0
    assert edit(path, "edge", "A", "C", "--no-render") == 0
    assert renders == [path]


def test_an_edit_writes_the_page_and_the_state_file(tmp_path, monkeypatch, capsys):
    path = tmp_path / "fx.dag.yaml"
    path.write_text(FX)
    monkeypatch.setattr(ad, "open_page", lambda p: pytest.fail("an edit opened a browser tab"))
    src = FakeSources(
        asks={"ab12": {"state": "open", "age_days": 0, "what": ""}, "cd34": {"state": "open", "age_days": 0, "what": ""}},
        probes={"test -e /tmp/x": 1},
        mrs={7: mr()},
    )
    assert ad.main(["set", str(path), "B", "--title", "Renamed step"], sources=src) == 0
    out = capsys.readouterr().out
    assert out.startswith("fx.dag.yaml: set B: title 'Renamed step'")
    assert f"Page: {tmp_path / 'fx.dag.html'}" in out and "Next for you:" in out
    assert "Renamed step" in (tmp_path / "fx.dag.html").read_text()
    assert json.loads((tmp_path / "fx.dag.state.json").read_text())["nodes"]["B"]["state"] == "next"


def test_refuses_when_the_file_changes_during_the_edit(fx, monkeypatch, capsys):
    path, renders = fx
    real = ad.EDITORS["set"]

    def racing(doc, args, src):
        path.write_text(FX + "# someone else\n")
        return real(doc, args, src)

    monkeypatch.setitem(ad.EDITORS, "set", racing)
    assert edit(path, "set", "B", "--sub", "x") == 1
    assert "changed while this command ran" in capsys.readouterr().err
    assert path.read_text().endswith("# someone else\n") and not renders


def test_edit_through_a_symlink_keeps_the_link_and_the_mode(tmp_path, fx):
    path, _ = fx
    path.chmod(0o600)
    link = tmp_path / "link.dag.yaml"
    link.symlink_to(path)
    assert ad.main(["set", str(link), "B", "--sub", "x", "--no-render"], sources=FakeSources()) == 0
    assert link.is_symlink() and "sub: x" in path.read_text()
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert not list(tmp_path.glob(".*.tmp"))


def test_goal_with_a_command_name_is_still_rendered(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(ad, "NOTEBOOK", tmp_path)
    (tmp_path / "set.dag.yaml").write_text(json.dumps({"goal": "set", "lanes": ["l1"], "nodes": [node("A", "next")]}))
    assert ad.main(["--no-open", "--", "set"], sources=FakeSources()) == 0
    assert (tmp_path / "set.dag.html").exists()
    with pytest.raises(SystemExit):  # `set` alone is the editing command
        ad.main(["set"], sources=FakeSources())


def test_editing_the_json_style_seed_still_validates(tmp_path, monkeypatch):
    # Graphs that other tests write are JSON (a YAML subset). ruamel.yaml keeps
    # them valid, but not byte for byte; the command says so.
    path = tmp_path / "j.dag.yaml"
    path.write_text(json.dumps({"goal": "j", "lanes": ["l1"], "nodes": [node("A", "next")]}))
    assert ad.main(["set", str(path), "A", "--state", "done", "--no-render"], sources=FakeSources()) == 0
    assert ad.load_graph(path).nodes["A"].sources == [{"manual": "done"}]


# ---------------------------------------------------------------- --public


@pytest.fixture
def pub(tmp_path, monkeypatch):
    """A graph with asks, local paths and wiki links, and a fake home directory."""
    home = tmp_path / "home" / "zed"
    monkeypatch.setenv("HOME", str(home))
    yml = tmp_path / "g.dag.yaml"
    yml.write_text(json.dumps({
        "goal": "g",
        "title": "Plan for f1db478",
        "summary": f"See {home}/notes/hub.md",
        "defaults": DEFAULTS,
        "lanes": [{"id": "l1", "title": "One"}, {"id": "l2", "title": "Two"}],
        "nodes": [
            node("A", {"ask": "a1"}, asks=["r9"], notes="Hub: [[eg6m|the hub note]] and [[0rfw]]."),
            node("B", [{"mr": 5}, {"ask": "a2"}], lane="l2", sub="commit f1db478 in ~/src/repo",
                 link="https://example.com/commit/f1db478"),
            node("C", {"probe": f"test -e {home}/x"}, lane="l2", notes="Run `$HOME/bin/tool`."),
        ],
        "edges": [["A", "B"]],
        "done": [{"label": "old [[zz11|first MR]]", "link": "https://example.com/old"}],
    }))
    src = FakeSources(
        asks={
            "a1": {"state": "done", "age_days": 0, "what": ""},
            "a2": {"state": "open", "age_days": 0, "what": ""},
            "r9": {"state": "open", "age_days": 30, "what": ""},
        },
        notes={"a1": "# SECRETASKTEXT\n", "a2": "# OTHERASKTEXT\n", "r9": "# RELATEDTEXT\n"},
        mrs={5: {**mr(state="merged"), "title": f"Fix {home}/x"}},
        probes={f"test -e {home}/x": {"rc": 1, "stderr": f"no {home}/x"}},
    )
    return yml, home, src


def test_public_removes_all_ask_data(pub, capsys):
    yml, _, src = pub
    assert ad.main([str(yml), "--public"], sources=src) == 0
    page = (yml.parent / "g.public.dag.html").read_text()
    for text in ("SECRETASKTEXT", "OTHERASKTEXT", "RELATEDTEXT", "ask a1", "ask a2", "ask r9",
                 "Related ask", "is stale", "tick the ask", "/notebook/"):
        assert text not in page, text
    # The nodes keep the state that the asks give.
    assert 'class="node s-done" id="n-A"' in page
    assert "private note closed" in page
    out = capsys.readouterr().out
    assert "removed 3 ask references, 2 ask warnings" in out


def test_public_strips_local_paths_and_wiki_links(pub, capsys):
    yml, home, src = pub
    assert ad.main([str(yml), "--public"], sources=src) == 0
    page = (yml.parent / "g.public.dag.html").read_text()
    assert str(home) not in page and "~/" not in page and "$HOME" not in page
    assert "[local path]" in page
    assert "[[" not in page and "eg6m" not in page and "0rfw" not in page and "zz11" not in page
    assert "Hub: the hub note and ." in page and "old first MR" in page
    assert '[ ["n-A", "n-B"]]' in page  # the edge list is still there, without "[["
    out = capsys.readouterr().out
    assert "3 wiki links" in out and "local paths" in out


def test_public_redact_pattern_removes_text_but_keeps_urls(pub, capsys):
    yml, _, src = pub
    assert ad.main([str(yml), "--public", "--redact-pattern", r"\bf1db478\b",
                    "--redact-pattern", "Plan"], sources=src) == 0
    page = (yml.parent / "g.public.dag.html").read_text()
    assert "<title> for </title>" in page
    assert "commit  in" in page
    assert page.count("f1db478") == 1 and "https://example.com/commit/f1db478" in page
    assert "3 --redact-pattern matches" in capsys.readouterr().out


def test_public_writes_no_state_file_and_keeps_the_normal_page(pub, tmp_path):
    yml, _, src = pub
    normal = yml.parent / "g.dag.html"
    normal.write_text("normal page")
    state = yml.parent / "g.dag.state.json"
    out = tmp_path / "share" / "x.html"
    assert ad.main([str(yml), "--public", "--output", str(out)], sources=src) == 0
    assert out.exists() and not (yml.parent / "g.public.dag.html").exists()
    assert normal.read_text() == "normal page"
    assert not state.exists()
    page = out.read_text()
    assert "http-equiv" not in page and "const RELOAD = 0;" in page
    # An old state file stays as it was, and the page shows no changes.
    state.write_text(json.dumps({"generated": "x", "nodes": {"A": {"state": "next", "detail": ""}}}))
    before = state.read_text()
    assert ad.main([str(yml), "--public", "--output", str(out)], sources=src) == 0
    assert state.read_text() == before
    assert 'title="Changed since the last run"' not in out.read_text()
    assert not list(yml.parent.glob(".*.tmp"))


def test_public_self_check_fails_and_writes_nothing(pub, tmp_path, monkeypatch, capsys):
    yml, home, src = pub
    template = tmp_path / "leaky.html"
    template.write_text(ad.TEMPLATE.read_text() + f"<!-- {home}/leak -->")
    monkeypatch.setattr(ad, "TEMPLATE", template)
    assert ad.main([str(yml), "--public"], sources=src) == 1
    assert "still contains the home directory path" in capsys.readouterr().err
    assert not (yml.parent / "g.public.dag.html").exists()
    assert not list(yml.parent.glob(".*.tmp"))


def test_public_option_errors(pub):
    yml, _, src = pub
    for argv in (
        ["--output", "x.html"],
        ["--redact-pattern", "x"],
        ["--public", "--json"],
        ["--public", "--watch"],
        ["--public", "--redact-pattern", "("],
    ):
        with pytest.raises(SystemExit):
            ad.main([str(yml), *argv], sources=src)
    assert ad.main([str(yml), "--public", "--output", str(yml)], sources=src) == 2


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q", "-p", "no:cacheprovider"]))
