#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["rich"]
# ///
"""herdr-mr-review — paste a GitHub PR / GitLab MR URL, check it out, and open a
herdr workspace laid out for review: a terminal pane (left) and Hunk
auto-refreshing the PR/MR diff (right).

Ported from the tmux `tmux-mr-review` popup. Runs under `uv run` so PyPI
dependencies can be added later just by editing the inline metadata block above
(none are needed today — everything here is stdlib).

Every invocation writes a full timestamped log to
$XDG_STATE_HOME/herdr-mr-review/ (default ~/.local/state/herdr-mr-review/), so a
failure inside the closing herdr pane is never silent again.
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path

from rich.console import Console
from rich.prompt import Prompt

console = Console(stderr=True)

WORK_ROOT = Path(os.environ.get("HERDR_MR_WORKDIR", str(Path.home() / "Work"))).expanduser()


# --------------------------------------------------------------------------- #
# Logging: one timestamped file per invocation, plus a size-capped rolling
# `latest.log`. Console output (stderr) goes to the herdr pane too.
# --------------------------------------------------------------------------- #
def setup_logging() -> tuple[logging.Logger, Path]:
    state = Path(
        os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
    ).expanduser() / "herdr-mr-review"
    state.mkdir(parents=True, exist_ok=True)

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    per_run = state / f"{stamp}-{os.getpid()}.log"

    log = logging.getLogger("herdr-mr-review")
    log.setLevel(logging.DEBUG)
    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(message)s")

    # Per-invocation file (full DEBUG detail).
    fh = logging.FileHandler(per_run, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    log.addHandler(fh)

    # Rolling `latest.log` (1 MB × 5) for quick `tail -f` without hunting stamps.
    rh = RotatingFileHandler(state / "latest.log", maxBytes=1_000_000, backupCount=5, encoding="utf-8")
    rh.setLevel(logging.DEBUG)
    rh.setFormatter(fmt)
    log.addHandler(rh)

    # Console (herdr pane) is deliberately quiet: WARNING and up only, so a
    # normal run shows just the prompt + a one-line result. Everything (incl. the
    # log path and every command) still lands in the files above.
    ch = logging.StreamHandler(sys.stderr)
    ch.setLevel(logging.WARNING)
    ch.setFormatter(logging.Formatter("%(message)s"))
    log.addHandler(ch)

    log.debug("log: %s", per_run)
    return log, per_run


LOG, LOG_PATH = setup_logging()


def run(
    *args: str,
    cwd: Path | None = None,
    check: bool = True,
    capture: bool = True,
) -> subprocess.CompletedProcess:
    """Run a command, logging argv + output. Raises on failure when check=True."""
    LOG.debug("$ %s%s", " ".join(args), f"  (cwd={cwd})" if cwd else "")
    proc = subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        text=True,
        capture_output=capture,
    )
    if capture:
        if proc.stdout.strip():
            LOG.debug("stdout: %s", proc.stdout.strip())
        if proc.stderr.strip():
            LOG.debug("stderr: %s", proc.stderr.strip())
    if check and proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, args, proc.stdout, proc.stderr)
    return proc


def die(msg: str, code: int = 1) -> None:
    LOG.error("Error: %s", msg)  # WARNING+ → also shows on console
    console.print(f"[dim]log: {LOG_PATH}[/dim]")
    # Keep the herdr pane open long enough to read the message before it closes.
    try:
        Prompt.ask("\n[dim]Press enter to close[/dim]", default="", show_default=False)
    except (EOFError, KeyboardInterrupt):
        pass
    sys.exit(code)


# --------------------------------------------------------------------------- #
# URL parsing
# --------------------------------------------------------------------------- #
GITHUB_RE = re.compile(r"^https://github\.com/(?P<project>[^/]+/[^/]+)/pull/(?P<n>\d+)")
GITLAB_RE = re.compile(r"^https://(?P<host>[^/]+)/(?P<project>.+)/-/merge_requests/(?P<n>\d+)")


class Target:
    def __init__(self, forge: str, host: str, project: str, number: str):
        self.forge = forge
        self.host = host
        self.project = project.removesuffix(".git")
        self.number = number
        self.review_branch = f"pr-{number}" if forge == "github" else f"mr-{number}"
        self.head_ref = (
            f"refs/pull/{number}/head"
            if forge == "github"
            else f"refs/merge-requests/{number}/head"
        )

    @property
    def repo_dir(self) -> Path:
        return WORK_ROOT / self.host / self.project

    @property
    def worktree_dir(self) -> Path:
        return self.repo_dir / ".zn-work" / f"{self.forge}-{self.number}"

    @property
    def label(self) -> str:
        return f"review/{Path(self.project).name}/{self.forge}-{self.number}"


def parse_url(raw: str) -> Target:
    # Extract the first URL — inside a pane, terminal capability replies can leak
    # stray bytes into stdin, so don't trust the raw field verbatim.
    m_url = re.search(r"https?://\S+", raw)
    url = m_url.group(0) if m_url else raw.strip()
    if m := GITHUB_RE.match(url):
        return Target("github", "github.com", m["project"], m["n"])
    if m := GITLAB_RE.match(url):
        return Target("gitlab", m["host"], m["project"], m["n"])
    die(f"Not a recognized GitHub PR or GitLab MR URL:\n  {url}")
    raise AssertionError  # unreachable


# --------------------------------------------------------------------------- #
# Forge API: resolve the contributor's source remote + branch (fork-aware).
# Returns (source_remote, source_branch, fork_url) or (None, None, None).
# --------------------------------------------------------------------------- #
def resolve_source(t: Target) -> tuple[str | None, str | None, str | None]:
    try:
        if t.forge == "github":
            p = run(
                "gh", "pr", "view", t.number, "--repo", t.project,
                "--json", "headRefName,headRepositoryOwner,headRepository,isCrossRepository",
                check=False,
            )
            if p.returncode != 0:
                return None, None, None
            j = json.loads(p.stdout)
            branch = j.get("headRefName")
            if j.get("isCrossRepository"):
                owner = j["headRepositoryOwner"]["login"]
                repo = j["headRepository"]["name"]
                return owner, branch, f"git@{t.host}:{owner}/{repo}.git"
            return "origin", branch, None
        else:
            p = run("glab", "mr", "view", t.number, "--repo", t.project, "--output", "json", check=False)
            if p.returncode != 0:
                return None, None, None
            j = json.loads(p.stdout)
            branch = j.get("source_branch")
            src, tgt = j.get("source_project_id"), j.get("target_project_id")
            if src and src != tgt:
                pj = run("glab", "api", f"projects/{src}", check=False)
                if pj.returncode == 0:
                    proj = json.loads(pj.stdout)
                    remote = proj["path_with_namespace"].replace("/", "-")
                    return remote, branch, proj["ssh_url_to_repo"]
            return "origin", branch, None
    except (json.JSONDecodeError, KeyError) as e:
        LOG.debug("forge API parse failed: %s", e)
        return None, None, None


def checkout_start_point(t: Target) -> str:
    """Fetch the review head and return a git start-point ref for the worktree.

    Tries the forge API's source branch first (named branch, pullable). If that
    branch no longer exists on the remote — merged+deleted, or a fork whose
    branch is gone — the fetch fails, so we fall back to the forge head ref
    (refs/pull/N/head, refs/merge-requests/N/head), which always resolves. This
    fallback is the fix for the old bash version dying on `couldn't find remote
    ref`.
    """
    remote, branch, fork_url = resolve_source(t)

    if branch:
        if remote and remote != "origin" and fork_url:
            # Add the fork remote (idempotent).
            if run("git", "-C", str(t.repo_dir), "remote", "get-url", remote, check=False).returncode != 0:
                run("git", "-C", str(t.repo_dir), "remote", "add", remote, fork_url)
        fetch = run(
            "git", "-C", str(t.repo_dir), "fetch", "-q", remote or "origin",
            f"+refs/heads/{branch}:refs/remotes/{remote or 'origin'}/{branch}",
            check=False,
        )
        if fetch.returncode == 0:
            return f"{remote or 'origin'}/{branch}"
        LOG.info("source branch %r not fetchable (deleted/fork); falling back to head ref", branch)

    # Fallback: forge head ref, always present for an open-or-merged PR/MR.
    local_ref = f"refs/review/{t.forge}-{t.number}"
    fetch = run(
        "git", "-C", str(t.repo_dir), "fetch", "-q", "origin", f"+{t.head_ref}:{local_ref}",
        check=False,
    )
    if fetch.returncode != 0:
        die(
            f"could not fetch {t.head_ref} — is the URL right / do you have access?\n"
            f"  {fetch.stderr.strip()}"
        )
    return local_ref


# --------------------------------------------------------------------------- #
# Base branch (repo default) for the review diff.
# --------------------------------------------------------------------------- #
def resolve_base(t: Target) -> str:
    p = run(
        "git", "-C", str(t.repo_dir), "symbolic-ref", "--short", "refs/remotes/origin/HEAD",
        check=False,
    )
    base = p.stdout.strip()
    if not base:
        run("git", "-C", str(t.repo_dir), "remote", "set-head", "origin", "--auto", check=False)
        p = run(
            "git", "-C", str(t.repo_dir), "symbolic-ref", "--short", "refs/remotes/origin/HEAD",
            check=False,
        )
        base = p.stdout.strip() or "origin/main"
    # Refresh so base...HEAD doesn't show already-merged commits (best effort).
    run("git", "-C", str(t.repo_dir), "fetch", "-q", "origin", base.removeprefix("origin/"), check=False)
    return base


# --------------------------------------------------------------------------- #
# herdr helpers
# --------------------------------------------------------------------------- #
def herdr_json(*args: str) -> dict:
    p = run("herdr", *args, check=False)
    if p.returncode != 0:
        return {}
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return {}


def existing_workspace(label: str) -> str | None:
    data = herdr_json("workspace", "list")
    for ws in data.get("result", {}).get("workspaces", []):
        if ws.get("label") == label:
            return ws.get("workspace_id")
    return None


def open_review_workspace(t: Target, base: str) -> None:
    # Idempotent: focus an existing review workspace instead of duplicating.
    if wsid := existing_workspace(t.label):
        LOG.info("workspace %s already open (%s); focusing", t.label, wsid)
        run("herdr", "workspace", "focus", wsid, check=False)
        return

    created = herdr_json(
        "workspace", "create", "--cwd", str(t.worktree_dir), "--label", t.label, "--focus"
    )
    root_pane = created.get("result", {}).get("root_pane", {}).get("pane_id")
    if not root_pane:
        die("herdr workspace create did not return a root pane id")

    # Split off the Hunk review pane (right, 62%). `herdr pane split` only makes
    # an interactive shell, so capture the new pane id and drive the command in
    # with `herdr pane run`.
    split = herdr_json(
        "pane", "split", root_pane, "--direction", "right", "--ratio", "0.62",
        "--cwd", str(t.worktree_dir), "--focus",
    )
    hunk_pane = split.get("result", {}).get("pane", {}).get("pane_id")
    if hunk_pane:
        run("herdr", "pane", "run", hunk_pane, f"hunk diff '{base}...HEAD' --watch", check=False)
    else:
        LOG.warning("could not split Hunk pane; workspace opened terminal-only")


# --------------------------------------------------------------------------- #
def main() -> None:
    raw = " ".join(sys.argv[1:]).strip()
    if not raw:
        # Prompt with rich (reads stdin directly — no subprocess/capture, which
        # is what broke the old `gum input` here). Styled, paste-friendly.
        console.print("[bold]Review a GitHub PR / GitLab MR in Hunk[/bold]")
        try:
            raw = Prompt.ask("[cyan]PR/MR URL[/cyan]", default="", show_default=False).strip()
        except (EOFError, KeyboardInterrupt):
            raw = ""
    if not raw:
        LOG.debug("no URL entered; cancelled")
        return

    t = parse_url(raw)
    LOG.debug("reviewing %s %s#%s", t.forge, t.project, t.number)
    console.print(f"[dim]→ {t.forge} {t.project}#{t.number}[/dim]")

    # Clone the repo once if we don't have it.
    if not (t.repo_dir / ".git").exists():
        console.print(f"[dim]cloning {t.project}…[/dim]")
        t.repo_dir.parent.mkdir(parents=True, exist_ok=True)
        run("git", "clone", f"git@{t.host}:{t.project}.git", str(t.repo_dir))

    start_point = checkout_start_point(t)
    base = resolve_base(t)

    # Create/refresh the worktree on the review branch.
    if t.worktree_dir.exists():
        run("git", "-C", str(t.worktree_dir), "checkout", "-q", "-B", t.review_branch, start_point, check=False)
    else:
        t.worktree_dir.parent.mkdir(parents=True, exist_ok=True)
        run("git", "-C", str(t.repo_dir), "worktree", "add", "-q", "-B", t.review_branch,
            str(t.worktree_dir), start_point)

    open_review_workspace(t, base)
    LOG.debug("done: %s", t.label)
    console.print(f"[green]✓[/green] {t.label}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        die(f"command failed ({e.returncode}): {' '.join(e.cmd)}\n  {(e.stderr or '').strip()}")
    except Exception as e:  # noqa: BLE001 — last-resort: log + keep pane open
        LOG.exception("unexpected failure")
        die(str(e))
