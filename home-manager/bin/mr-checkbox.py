#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Tick or clear one checkbox line in a GitLab MR description.

    mr-checkbox <project-path> <iid> --match "<text>" --check|--uncheck
                [--append " (evidence)"] [--dry-run] [--hostname HOST]

The script reads the description with a `glab api` GET request. It finds the
one task-list line (`- [ ] ...` or `- [x] ...`) that contains the --match
text, and changes only that line. If no line or more than one line matches, it
stops and changes nothing. It writes the description back with
`glab mr update --description`.

The project is always a path (`group/sub/repo`), never a numeric id. An MR
number (iid) is unique in its project only, so a wrong numeric id changes the
MR of a different project.
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import subprocess
import sys
import urllib.parse

CALL_TIMEOUT = 60  # seconds, for one glab call
# A task-list item: indent, bullet, "[ ]" or "[x]", then the text.
CHECKBOX = re.compile(r"^(?P<pre>\s*[-*+]\s+\[)(?P<mark>[ xX])(?P<post>\]\s.*)$")


class CheckboxError(Exception):
    """The change is refused. Nothing was written."""


def glab(args: list[str]) -> str:
    try:
        p = subprocess.run(
            ["glab", *args], capture_output=True, text=True,
            timeout=CALL_TIMEOUT, stdin=subprocess.DEVNULL,
        )
    except FileNotFoundError as e:
        raise CheckboxError("glab is not on PATH") from e
    if p.returncode != 0:
        err = " ".join((p.stderr or p.stdout or "no error text").split())[:300]
        raise CheckboxError(f"glab {args[0]} failed: {err}")
    return p.stdout


def get_description(host: str, project: str, iid: int) -> str:
    path = f"projects/{urllib.parse.quote(project, safe='')}/merge_requests/{iid}"
    data = json.loads(glab(["api", "--hostname", host, path]))
    return data.get("description") or ""


def toggle(text: str, match: str, check: bool, append: str = "") -> tuple[str, str]:
    """Return (new text, the changed line). Raise CheckboxError unless exactly
    one checkbox line contains `match`."""
    lines = text.splitlines(keepends=True)
    hits = []
    for i, line in enumerate(lines):
        body = line.rstrip("\r\n")
        m = CHECKBOX.match(body)
        if m and match in body:
            hits.append((i, m, line[len(body):]))
    if not hits:
        raise CheckboxError(f"no checkbox line contains {match!r}")
    if len(hits) > 1:
        found = "\n".join(f"  {m.group(0)}" for _, m, _ in hits)
        raise CheckboxError(f"{len(hits)} checkbox lines contain {match!r}; make --match longer:\n{found}")
    i, m, eol = hits[0]
    post = m.group("post")
    if append and not post.endswith(append):
        post += append
    new = f"{m.group('pre')}{'x' if check else ' '}{post}"
    lines[i] = new + eol
    return "".join(lines), new


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="mr-checkbox",
        description="Tick or clear exactly one `- [ ]` / `- [x]` line in a GitLab MR description.",
    )
    ap.add_argument("project", help="the project path, for example group/sub/repo (never a numeric id)")
    ap.add_argument("iid", type=int, help="the MR number in that project")
    ap.add_argument("--match", required=True, help="text that only the target checkbox line contains")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="tick the box: [x]")
    mode.add_argument("--uncheck", action="store_true", help="clear the box: [ ]")
    ap.add_argument("--append", default="", metavar="TEXT", help="add TEXT at the end of the line, if the line does not end with it")
    ap.add_argument("--dry-run", action="store_true", help="print the change as a unified diff. Write nothing")
    ap.add_argument(
        "--hostname", default=None,
        help="the GitLab host (default: $GITLAB_HOST, else the host from `glab config get host`)",
    )
    args = ap.parse_args(argv)
    project = args.project.strip("/")
    if project.isdigit() or "/" not in project:
        print(f"mr-checkbox: give the project path (group/repo), not {args.project!r}", file=sys.stderr)
        return 2
    ref = f"{project}!{args.iid}"
    try:
        if not args.hostname:
            args.hostname = os.environ.get("GITLAB_HOST") or glab(["config", "get", "host"]).strip()
        if not args.hostname:
            raise CheckboxError("no GitLab host. Give --hostname or set GITLAB_HOST")
        old = get_description(args.hostname, project, args.iid)
        new, line = toggle(old, args.match, args.check, args.append)
        if new == old:
            print(f"{ref}: no change, the line is already: {line.strip()}")
            return 0
        if args.dry_run:
            sys.stdout.writelines(difflib.unified_diff(
                old.splitlines(keepends=True), new.splitlines(keepends=True),
                fromfile=f"{ref} description", tofile=f"{ref} description",
            ))
            print(f"\ndry run, nothing written: {line.strip()}")
            return 0
        # Somebody can edit the description between the read and the write.
        if get_description(args.hostname, project, args.iid) != old:
            raise CheckboxError("the description changed while this command ran. Nothing was written. Run the command again")
        glab([
            "mr", "update", str(args.iid),
            "--repo", f"https://{args.hostname}/{project}",
            "--description", new,
        ])
        if line not in get_description(args.hostname, project, args.iid).splitlines():
            raise CheckboxError("glab mr update ran, but the new line is not in the description. Check the MR")
    except CheckboxError as e:
        print(f"mr-checkbox: {e}", file=sys.stderr)
        return 1
    print(f"{ref}: {line.strip()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
