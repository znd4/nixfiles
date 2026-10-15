#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pytest>=8"]
# ///
"""Tests for ../mr-checkbox.py.

Run: uv run --script home-manager/bin/tests/test_mr_checkbox.py

The tests never call the real glab. A fake `glab` on PATH serves the
description from a file, logs its arguments, and stores the new description
that `glab mr update` gives it.
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
SPEC = importlib.util.spec_from_file_location("mr_checkbox", HERE.parent / "mr-checkbox.py")
mc = importlib.util.module_from_spec(SPEC)
sys.modules["mr_checkbox"] = mc
SPEC.loader.exec_module(mc)

DESC = """\
## What

Move the thing.

## Before merge

- [ ] CI is green on the parent
- [x] Reviewer approved
  * [ ] nested: plan shows 0 to destroy\r
- [ ] Rollback tested

Not a box: [ ] CI
"""


@pytest.fixture
def fake_glab(tmp_path, monkeypatch):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    store = tmp_path / "desc.txt"
    store.write_text(DESC, newline="")
    log = tmp_path / "calls.log"
    helper = tmp_path / "fake_glab.py"
    helper.write_text(
        "import json, sys\n"
        f"store, log = {str(store)!r}, {str(log)!r}\n"
        "args = sys.argv[1:]\n"
        "open(log, 'a').write(json.dumps(args) + '\\n')\n"
        "if args[0] == 'api':\n"
        "    print(json.dumps({'description': open(store, newline='').read()}))\n"
        "elif args[:2] == ['mr', 'update']:\n"
        "    open(store, 'w', newline='').write(args[args.index('--description') + 1])\n"
        "else:\n"
        "    sys.exit(3)\n"
    )
    exe = bindir / "glab"
    exe.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{helper}" "$@"\n')
    exe.chmod(exe.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setenv("PATH", f"{bindir}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("GITLAB_HOST", "gitlab.example.com")
    return store, log


def calls(log):
    return [json.loads(x) for x in log.read_text().splitlines()] if log.exists() else []


def test_check_changes_exactly_one_line(fake_glab, capsys):
    store, log = fake_glab
    assert mc.main(["group/sub repo", "12", "--match", "parent", "--check", "--append", " (pipeline 9)"]) == 0
    new = store.read_text(newline="")
    assert new == DESC.replace("- [ ] CI is green on the parent", "- [x] CI is green on the parent (pipeline 9)")
    c = calls(log)
    assert c[0] == ["api", "--hostname", "gitlab.example.com", "projects/group%2Fsub%20repo/merge_requests/12"]
    update = next(x for x in c if x[0] == "mr")
    assert update[:5] == ["mr", "update", "12", "--repo", "https://gitlab.example.com/group/sub repo"]
    assert "group/sub repo!12: - [x] CI is green on the parent (pipeline 9)" in capsys.readouterr().out


def test_uncheck_keeps_a_crlf_line_end_and_the_indent(fake_glab):
    store, _ = fake_glab
    assert mc.main(["g/r", "1", "--match", "nested", "--check"]) == 0
    assert "  * [x] nested: plan shows 0 to destroy\r\n" in store.read_text(newline="")
    assert mc.main(["g/r", "1", "--match", "Reviewer", "--uncheck"]) == 0
    assert "- [ ] Reviewer approved\n" in store.read_text(newline="")


def test_zero_or_many_matches_are_refused(fake_glab, capsys):
    store, log = fake_glab
    assert mc.main(["g/r", "1", "--match", "nothing like this", "--check"]) == 1
    assert "no checkbox line" in capsys.readouterr().err
    assert mc.main(["g/r", "1", "--match", "e", "--check"]) == 1
    err = capsys.readouterr().err
    assert "4 checkbox lines" in err and "Not a box" not in err
    assert store.read_text(newline="") == DESC
    assert not any(x[0] == "mr" for x in calls(log))


def test_dry_run_prints_the_diff_and_writes_nothing(fake_glab, capsys):
    store, log = fake_glab
    assert mc.main(["g/r", "1", "--match", "Rollback", "--check", "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert "-- [ ] Rollback tested" in out and "+- [x] Rollback tested" in out
    assert store.read_text(newline="") == DESC
    assert not any(x[0] == "mr" for x in calls(log))


def test_no_change_when_already_in_that_state(fake_glab, capsys):
    _, log = fake_glab
    assert mc.main(["g/r", "1", "--match", "Reviewer", "--check"]) == 0
    assert "no change" in capsys.readouterr().out
    assert not any(x[0] == "mr" for x in calls(log))


def test_numeric_project_id_is_refused(fake_glab, capsys):
    _, log = fake_glab
    assert mc.main(["1234", "1", "--match", "CI", "--check"]) == 2
    assert "project path" in capsys.readouterr().err
    assert not calls(log)


def test_hostname_option(fake_glab):
    _, log = fake_glab
    assert mc.main(["g/r", "1", "--match", "Rollback", "--check", "--hostname", "other.example.com"]) == 0
    c = calls(log)
    assert c[0][:3] == ["api", "--hostname", "other.example.com"]
    assert "https://other.example.com/g/r" in next(x for x in c if x[0] == "mr")


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q", "-p", "no:cacheprovider"]))
