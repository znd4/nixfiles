#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pytest"]
# ///
"""Headless tests for the pure matcher/hint layer of herdr-thumbs.

Run:  uv run test_thumbs.py        (invokes pytest on this file)
"""
import re
import subprocess
import sys
from pathlib import Path

import pytest

import thumbs
from thumbs import Config, Match, assign_hints, find_matches, gen_hints, run_action


def _pats(*regexes):
    return [re.compile(r) for r in regexes]


# --------------------------------------------------------------------------- #
# find_matches
# --------------------------------------------------------------------------- #


def test_finds_url():
    lines = ["visit https://example.com/foo now"]
    m = find_matches(lines, thumbs.Config.load().compiled)
    texts = [x.text for x in m]
    assert "https://example.com/foo" in texts


def test_url_trailing_punct_trimmed():
    lines = ["see (https://example.com/foo)."]
    m = find_matches(lines, _pats(thumbs.DEFAULT_PATTERNS[0]))
    assert m[0].text == "https://example.com/foo"


def test_git_remote():
    lines = ["origin git@github.com:znd4/herdr-thumbs.git (fetch)"]
    m = find_matches(lines, _pats(thumbs.DEFAULT_PATTERNS[0]))
    assert m[0].text.startswith("git@github.com:znd4/herdr-thumbs")


def test_sha_and_uuid():
    lines = ["commit a1b2c3d4e5f6 uuid 12345678-1234-1234-1234-1234567890ab"]
    cfg = Config.load()
    m = find_matches(lines, cfg.compiled)
    texts = [x.text for x in m]
    assert "a1b2c3d4e5f6" in texts
    assert "12345678-1234-1234-1234-1234567890ab" in texts


def test_ip_and_hostport():
    lines = ["bind 127.0.0.1:8080 and localhost:4321"]
    cfg = Config.load()
    texts = [x.text for x in find_matches(lines, cfg.compiled)]
    assert "127.0.0.1:8080" in texts
    assert "localhost:4321" in texts


def test_no_overlap_priority():
    # A URL that also contains something a later pattern could match:
    # the URL (pattern 0) must win the whole span, no double hint.
    lines = ["http://127.0.0.1:8080/path"]
    cfg = Config.load()
    m = find_matches(lines, cfg.compiled)
    assert len(m) == 1
    assert m[0].text == "http://127.0.0.1:8080/path"


def test_positions_are_correct():
    lines = ["xx https://a.com yy"]
    m = find_matches(lines, _pats(thumbs.DEFAULT_PATTERNS[0]))
    assert m[0].row == 0
    assert m[0].col == 3
    assert lines[0][m[0].col:m[0].col + len(m[0].text)] == m[0].text


def test_empty():
    assert find_matches(["nothing here", ""], Config.load().compiled) == []


# --------------------------------------------------------------------------- #
# gen_hints
# --------------------------------------------------------------------------- #


def test_gen_hints_single():
    h = gen_hints(3, "asdf")
    assert h == ["a", "s", "d"]


def test_gen_hints_all_singles():
    h = gen_hints(4, "asdf")
    assert h == ["a", "s", "d", "f"]


def test_gen_hints_two_char_when_overflow():
    h = gen_hints(6, "asdf")  # 4 singles not enough
    assert len(h) == 6
    assert len(set(h)) == 6  # unique
    # no single hint should be a prefix of a two-char hint
    singles = [x for x in h if len(x) == 1]
    doubles = [x for x in h if len(x) == 2]
    for s in singles:
        assert not any(d.startswith(s) for d in doubles), (s, doubles)


def test_gen_hints_large():
    h = gen_hints(50, thumbs.DEFAULT_ALPHABET)
    assert len(h) == 50
    assert len(set(h)) == 50


# --------------------------------------------------------------------------- #
# assign_hints
# --------------------------------------------------------------------------- #


def test_assign_hints_unique_and_shortest_at_bottom_right():
    matches = [
        Match(row=0, col=0, text="a"),
        Match(row=5, col=40, text="b"),  # bottom-right -> shortest hint
        Match(row=2, col=10, text="c"),
    ]
    # force overflow so some hints are 2-char
    assign_hints(matches, "as")  # only 2 singles, 3 matches -> overflow
    hints = {m.text: m.hint for m in matches}
    assert len(set(hints.values())) == 3
    # bottom-right (text "b") should get a single-char hint
    assert len(hints["b"]) == 1


# --------------------------------------------------------------------------- #
# actions (injected, no real herdr / clipboard)
# --------------------------------------------------------------------------- #


def test_run_action_argv_substitution(monkeypatch):
    calls = {}

    def fake_run(cmd, **kw):
        calls["cmd"] = cmd
        calls["kw"] = kw
        class R: returncode = 0
        return R()

    monkeypatch.setattr(thumbs.subprocess, "run", fake_run)
    run_action(["open", "{}"], "https://x.com", via_stdin=False)
    assert calls["cmd"] == ["open", "https://x.com"]
    assert "input" not in calls["kw"]


def test_run_action_stdin(monkeypatch):
    calls = {}

    def fake_run(cmd, **kw):
        calls["cmd"] = cmd
        calls["kw"] = kw
        class R: returncode = 0
        return R()

    monkeypatch.setattr(thumbs.subprocess, "run", fake_run)
    run_action(["pbcopy"], "hello", via_stdin=True)
    assert calls["cmd"] == ["pbcopy"]
    assert calls["kw"]["input"] == "hello"


# --------------------------------------------------------------------------- #
# focused_pane_id context parsing
# --------------------------------------------------------------------------- #


def test_focused_pane_from_context_real_key(monkeypatch):
    # The real herdr 0.7.1 shape: flat `focused_pane_id`, and HERDR_PANE_ID is
    # the overlay's own pane, which must be ignored.
    monkeypatch.setenv(
        "HERDR_PLUGIN_CONTEXT_JSON",
        '{"workspace_id":"wN","focused_pane_id":"wN:p1","invocation_source":"api"}',
    )
    monkeypatch.setenv("HERDR_PANE_ID", "wN:pF")  # overlay's own pane
    assert thumbs.focused_pane_id() == "wN:p1"


def test_focused_pane_nested_shape(monkeypatch):
    monkeypatch.setenv(
        "HERDR_PLUGIN_CONTEXT_JSON",
        '{"focused_pane": {"pane_id": "w1:p2"}}',
    )
    monkeypatch.delenv("HERDR_PANE_ID", raising=False)
    assert thumbs.focused_pane_id() == "w1:p2"


def test_focused_pane_fallback_env_no_context(monkeypatch):
    monkeypatch.delenv("HERDR_PLUGIN_CONTEXT_JSON", raising=False)
    monkeypatch.setenv("HERDR_PANE_ID", "w9:p9")
    assert thumbs.focused_pane_id() == "w9:p9"


if __name__ == "__main__":
    sys.exit(pytest.main([str(Path(__file__)), "-q"]))
