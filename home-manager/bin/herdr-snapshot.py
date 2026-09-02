#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Save herdr session state to disk so you can recover sessions after a crash.

herdr keeps workspace labels, layout, and working directories across a server
crash. It does not keep the Claude Code session UUID for each pane. Without that
UUID you cannot run `claude --resume <uuid>`, and each killed session becomes
unreachable. One crash lost 12 sessions this way.

`herdr api snapshot` prints the layout and agents in one call. This script runs
that command and writes the result. It does not read the socket directly.

WHY THE SCRIPT ADDS DATA TO THE SNAPSHOT
-----------------------------------------
herdr knows a pane's session UUID only if the Claude Code SessionStart hook
reported it. That report goes to the herdr socket. herdr discards the report
silently if the server is not listening -- exactly the condition after a crash,
while the server restarts and sessions come back. On this machine only 3 of 14
live panes had a UUID for that reason.

The script finds the missing UUIDs itself at capture time:

    pane -> `herdr pane process-info` -> claude pid -> ~/.claude/sessions/<pid>.json

~/.claude/sessions/<pid>.json holds `sessionId` and `cwd` for every live Claude
Code process, whatever command started it. These files describe live processes
only and do not survive a crash. The capture must therefore run periodically
while the sessions still run.

The result goes in a `sessions` field beside `snapshot`. The herdr output stays
unchanged. Each entry says in `source` where its UUID came from:

    "herdr"   -- herdr reported it.
    "pid"     -- this script found it through the pid of the pane.
    "unknown" -- no UUID found. The pane cannot resume.

The script also reports each recovered UUID back to herdr with
`herdr pane report-agent-session`. herdr's state repairs itself, and later
snapshots need less work. Set HERDR_SNAPSHOT_NO_REPORT=1 to disable this.

OUTPUT
------
In ~/.local/state/herdr-snapshots:

    latest.json            the newest state
    snapshot-<epoch>.json  the history, about 7 days

Each file has this format:

    {"capturedAt": "<ISO 8601 UTC>",
     "snapshot":   <the output of `herdr api snapshot`, unchanged>,
     "sessions":   [{"paneId": ..., "sessionId": ..., "source": ...}, ...]}

Read the layout from `.snapshot.result.snapshot` and the session UUIDs from
`.sessions[]`.

Each file is written to a temporary path and then renamed, so a crash during a
write cannot damage latest.json. The script exits 0 and prints nothing if the
herdr server is not running: at night this is normal, not an error.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

# 336 files = 7 days at one snapshot every 30 minutes.
KEEP = 336
SNAPSHOT_TIMEOUT = 20
PANE_TIMEOUT = 5

STATE_DIR = Path(
    os.environ.get("HERDR_SNAPSHOT_DIR")
    or Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    / "herdr-snapshots"
)
LATEST = STATE_DIR / "latest.json"
CLAUDE_SESSION_DIR = Path.home() / ".claude" / "sessions"

# `herdr pane report-agent-session` requires a known `--source` value. herdr
# silently drops an unknown source with exit 0 -- "herdr-snapshot" looked correct
# but did nothing. Use the same value as the Claude Code hook: "herdr:claude".
REPORT_SOURCE = "herdr:claude"


# ---------------------------------------------------------------------------
# herdr


def socket_path() -> Path:
    """Give the path of the herdr API socket."""
    from_env = os.environ.get("HERDR_SOCKET_PATH")
    if from_env:
        return Path(from_env)
    config_home = os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
    return Path(config_home) / "herdr" / "herdr.sock"


def server_is_running() -> bool:
    """Tell if the herdr server listens on its socket."""
    try:
        return stat.S_ISSOCK(socket_path().stat().st_mode)
    except OSError:
        return False


def herdr_binary() -> str | None:
    """Give the path of the herdr program, or None if it is not installed."""
    return os.environ.get("HERDR_BIN") or shutil.which("herdr")


def run_herdr(herdr: str, args: list[str], timeout: int) -> dict | None:
    """Run a herdr command and give its parsed JSON, or None on any failure."""
    try:
        done = subprocess.run(
            [herdr, *args], capture_output=True, timeout=timeout, check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if done.returncode != 0 or not done.stdout.strip():
        return None
    try:
        parsed = json.loads(done.stdout)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def claude_pid_of_pane(herdr: str, pane_id: str) -> int | None:
    """Give the pid of the Claude Code process in a pane, or None."""
    reply = run_herdr(herdr, ["pane", "process-info", "--pane", pane_id], PANE_TIMEOUT)
    try:
        processes = reply["result"]["process_info"]["foreground_processes"]
    except (TypeError, KeyError):
        return None
    if not isinstance(processes, list):
        return None
    for process in processes:
        if not isinstance(process, dict):
            continue
        argv = process.get("argv") or []
        argv0 = process.get("argv0") or (argv[0] if argv else "")
        if argv0 == "claude" or argv0.endswith("/claude"):
            pid = process.get("pid")
            if isinstance(pid, int):
                return pid
    return None


def report_to_herdr(herdr: str, pane_id: str, session_id: str) -> None:
    """Tell herdr the session UUID of a pane, so that its state repairs itself."""
    subprocess.run(
        [
            herdr,
            "pane",
            "report-agent-session",
            pane_id,
            "--source",
            REPORT_SOURCE,
            "--agent",
            "claude",
            "--agent-session-id",
            session_id,
            "--seq",
            str(time.time_ns()),
        ],
        capture_output=True,
        timeout=PANE_TIMEOUT,
        check=False,
    )


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


def collect_sessions(herdr: str, snapshot: dict) -> list[dict]:
    """Build one entry per Claude Code pane, with its session UUID.

    An entry keeps `sessionId` empty if neither herdr nor the pid gave a UUID.
    Keep that entry: it records a pane whose session is unidentifiable.
    """
    try:
        agents = snapshot["result"]["snapshot"]["agents"]
    except (TypeError, KeyError):
        return []
    if not isinstance(agents, list):
        return []

    by_pid = live_claude_sessions()
    report_back = os.environ.get("HERDR_SNAPSHOT_NO_REPORT") != "1"
    entries: list[dict] = []

    for agent in agents:
        if not isinstance(agent, dict) or agent.get("agent") != "claude":
            continue
        pane_id = agent.get("pane_id")
        if not pane_id:
            continue

        entry = {
            "paneId": pane_id,
            "tabId": agent.get("tab_id"),
            "workspaceId": agent.get("workspace_id"),
            "cwd": agent.get("foreground_cwd") or agent.get("cwd"),
            "agentStatus": agent.get("agent_status"),
            "terminalTitle": agent.get("terminal_title_stripped")
            or agent.get("terminal_title"),
            "sessionId": None,
            "source": "unknown",
            "pid": None,
        }

        reported = (agent.get("agent_session") or {}).get("value")
        if reported:
            entry["sessionId"] = reported
            entry["source"] = "herdr"
            entries.append(entry)
            continue

        pid = claude_pid_of_pane(herdr, pane_id)
        record = by_pid.get(pid) if pid is not None else None
        if record:
            entry["sessionId"] = record["sessionId"]
            entry["source"] = "pid"
            entry["pid"] = pid
            entry["cwd"] = record.get("cwd") or entry["cwd"]
            if report_back:
                # Report the UUID to herdr so the next snapshot reads it from
                # `agent_session` directly, with no pid lookup.
                try:
                    report_to_herdr(herdr, pane_id, record["sessionId"])
                except (OSError, subprocess.SubprocessError):
                    pass
        entries.append(entry)

    return entries


# ---------------------------------------------------------------------------
# Files


def canonical(payload: object) -> str:
    """Give a stable text form of the payload, to compare two captures."""
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))


def previous_state() -> list | None:
    """Give the snapshot and the session list of latest.json, or None."""
    try:
        with LATEST.open(encoding="utf-8") as handle:
            document = json.load(handle)
        return [document["snapshot"], document.get("sessions")]
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
            json.dump(document, handle, sort_keys=True, separators=(",", ":"))
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
    if len(files) <= KEEP:
        return
    for old in files[:-KEEP]:
        try:
            old.unlink()
        except OSError:
            pass


# ---------------------------------------------------------------------------


def main() -> int:
    if not server_is_running():
        return 0
    herdr = herdr_binary()
    if herdr is None:
        return 0
    snapshot = run_herdr(herdr, ["api", "snapshot"], SNAPSHOT_TIMEOUT)
    if snapshot is None:
        # The server stopped between the socket check and this call.
        # Treat it the same as a stopped server: exit quietly.
        return 0

    sessions = collect_sessions(herdr, snapshot)

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    now = time.time()
    document = {
        "capturedAt": datetime.fromtimestamp(now, timezone.utc).isoformat(
            timespec="seconds"
        ),
        "snapshot": snapshot,
        "sessions": sessions,
    }

    previous = previous_state()
    unchanged = previous is not None and canonical(previous) == canonical(
        [snapshot, sessions]
    )
    if not unchanged:
        # Write a history file only when the state changed. An idle weekend
        # must not produce 336 identical files.
        write_atomically(STATE_DIR / f"snapshot-{int(now)}.json", document)
    write_atomically(LATEST, document)
    prune()
    return 0


if __name__ == "__main__":
    sys.exit(main())
