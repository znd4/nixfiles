#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Restore the Claude Code sessions in a tmux snapshot.

The script reads a file from tmux-snapshot.py (default: latest.json). For
each session, it opens a tmux pane in the saved cwd and runs
`claude --resume <uuid>` in that pane. Panes from one saved window go into one
new window.

By default the script does a dry run: it prints the tmux commands and changes
nothing. Add --apply to run the commands.

The script skips these entries:
    - An entry whose UUID a live Claude Code process already uses. Two
      processes on one transcript damage the session.
    - An entry that has no UUID.

The script only creates sessions, windows, and panes. It never closes,
renames, or moves a window or pane that exists.

Usage:
    tmux-restore [--apply] [--file PATH] [--only UUID[,UUID...]]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

STATE_DIR = Path(
    os.environ.get("TMUX_SNAPSHOT_DIR")
    or Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    / "tmux-snapshots"
)
CLAUDE_SESSION_DIR = Path.home() / ".claude" / "sessions"


def live_session_ids() -> set[str]:
    """Give the session UUIDs of all live Claude Code processes."""
    ids: set[str] = set()
    for path in CLAUDE_SESSION_DIR.glob("*.json"):
        try:
            os.kill(int(path.stem), 0)
            ids.add(json.loads(path.read_text(encoding="utf-8"))["sessionId"])
        except PermissionError:
            pass
        except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError):
            continue
    return ids


def has_session(name: str) -> bool:
    """Tell if a tmux session with exactly this name exists."""
    done = subprocess.run(
        ["tmux", "has-session", "-t", f"={name}"], capture_output=True, check=False
    )
    return done.returncode == 0


class Runner:
    """Print each tmux command, and run it when apply is true."""

    def __init__(self, apply: bool) -> None:
        self.apply = apply
        self.count = 0

    def new_pane(self, args: list[str]) -> str:
        """Run a command that creates a pane, and give the new pane id."""
        self.count += 1
        print("tmux " + shlex.join(args))
        if not self.apply:
            return f"<pane{self.count}>"
        done = subprocess.run(
            ["tmux", *args, "-P", "-F", "#{pane_id}"],
            capture_output=True,
            text=True,
            check=True,
        )
        return done.stdout.strip()

    def send(self, pane: str, command: str) -> None:
        """Type the command into the pane and press Enter."""
        args = ["send-keys", "-t", pane, command, "Enter"]
        print("tmux " + shlex.join(args))
        if self.apply:
            subprocess.run(["tmux", *args], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--apply", action="store_true", help="run the commands")
    parser.add_argument(
        "--file",
        type=Path,
        default=STATE_DIR / "latest.json",
        help="snapshot file to read (default: latest.json)",
    )
    parser.add_argument("--only", help="comma-separated session UUIDs to restore")
    args = parser.parse_args()

    document = json.loads(args.file.read_text(encoding="utf-8"))
    only = set(args.only.split(",")) if args.only else None
    live = live_session_ids()
    print(f"# snapshot {args.file} captured {document.get('capturedAt')}")

    runner = Runner(args.apply)
    sessions_made: set[str] = set()
    windows: dict[tuple[str, int], str] = {}
    entries = sorted(
        document.get("sessions", []),
        key=lambda e: (e["tmuxSession"], e["windowIndex"], e["paneIndex"]),
    )
    for entry in entries:
        uuid, cwd = entry.get("sessionId"), entry.get("cwd") or str(Path.home())
        where = f"{entry['tmuxSession']}:{entry['windowIndex']} {entry['windowName']}"
        if not uuid:
            print(f"# skip {where}: no session UUID (source {entry.get('source')})")
            continue
        if only is not None and uuid not in only:
            continue
        if uuid in live:
            print(f"# skip {where}: {uuid} is already running")
            continue

        session = entry["tmuxSession"]
        # tmux names a window after its process, and the claude process name
        # is its version number ("2.1.283"). Do not use that name.
        name = entry["windowName"]
        name_args = [] if re.fullmatch(r"[\d.]+", name) else ["-n", name]
        key = (session, entry["windowIndex"])
        if key in windows:
            pane = runner.new_pane(["split-window", "-t", windows[key], "-c", cwd])
        elif session in sessions_made or has_session(session):
            pane = runner.new_pane(
                ["new-window", "-t", f"={session}:", *name_args, "-c", cwd]
            )
        else:
            pane = runner.new_pane(
                ["new-session", "-d", "-s", session, *name_args, "-c", cwd]
            )
            sessions_made.add(session)
        windows.setdefault(key, pane)
        runner.send(pane, f"claude --resume {uuid}")

    if not args.apply:
        print("# dry run: nothing changed. Add --apply to run these commands.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
