#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""herdr-thumbs — tmux-thumbs for herdr.

Launched by herdr in a temporary *overlay* pane (see herdr-plugin.toml). The
overlay zooms over the active pane, captures keystrokes, and restores the
previous focus + zoom when we exit — the whole UX:

  1. read the content of the focused herdr pane (via `herdr pane read`)
  2. regex-match "hintable" strings (URLs, paths, hashes, …)
  3. draw a snapshot of that pane with a short hint label over each match
  4. read one hint from the user
     - lowercase hint  -> DEFAULT action  (copy to clipboard)
     - uppercase hint  -> UPCASE  action  (open in browser / default app)
  5. run the action, flash a confirmation, exit

Everything here is deliberately dependency-free (stdlib curses) so it stays a
single uv script. The matcher/action layer is import-safe and unit-testable
without a real herdr or tty — see test_thumbs.py.

Config: an optional TOML at $HERDR_PLUGIN_CONFIG_DIR/config.toml (falls back to
built-in defaults). See DEFAULT_CONFIG below for the schema.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #

# Hint alphabet: home-row-first, like tmux-thumbs' default. Two-char hints are
# generated automatically when there are more matches than single chars.
DEFAULT_ALPHABET = "asdfghjklqwertyuiopzxcvbnm"

# Ordered regexes. First match wins for overlapping spans. These mirror the old
# tmux-thumbs config (URL regexp-1) plus a few high-value extras.
DEFAULT_PATTERNS: list[str] = [
    # URLs / git remotes (the old @thumbs-regexp-1)
    r"(?:https?://|git@|git://|ssh://|ftp://|file:///)[^ \t\r\n]+[^.,;:)\]>\s]",
    # absolute + ~ + ./ paths
    r"(?:[.~]?/)[^ \t\r\n\"'`]+",
    # uuid (before the generic hex pattern, which would otherwise eat its parts)
    r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b",
    # git sha / hex blobs (7-40 chars)
    r"\b[0-9a-f]{7,40}\b",
    # ipv4[:port]
    r"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b",
    # bare hostname:port (e.g. localhost:4321)
    r"\b[a-zA-Z0-9._-]+:\d{2,5}\b",
]

# Actions are argv templates. "{}" is replaced with the matched string.
# `default` fires on a lowercase hint, `upcase` on an uppercase hint.
DEFAULT_CONFIG: dict = {
    "alphabet": DEFAULT_ALPHABET,
    "patterns": DEFAULT_PATTERNS,
    # copy to macOS clipboard by default; Linux users override to wl-copy/cb.
    "default_action": ["pbcopy"],
    "default_action_stdin": True,   # pass the match on stdin (pbcopy has no argv)
    "upcase_action": ["open", "{}"],
    "upcase_action_stdin": False,
}


@dataclass
class Config:
    alphabet: str
    patterns: list[str]
    default_action: list[str]
    default_action_stdin: bool
    upcase_action: list[str]
    upcase_action_stdin: bool
    compiled: list[re.Pattern] = field(default_factory=list)

    @classmethod
    def load(cls) -> "Config":
        data = dict(DEFAULT_CONFIG)
        cfg_dir = os.environ.get("HERDR_PLUGIN_CONFIG_DIR")
        if cfg_dir:
            p = Path(cfg_dir) / "config.toml"
            if p.is_file():
                try:
                    user = tomllib.loads(p.read_text())
                    data.update(user)
                except Exception as e:  # pragma: no cover - defensive
                    print(f"herdr-thumbs: bad config {p}: {e}", file=sys.stderr)
        c = cls(
            alphabet=data["alphabet"],
            patterns=list(data["patterns"]),
            default_action=list(data["default_action"]),
            default_action_stdin=bool(data["default_action_stdin"]),
            upcase_action=list(data["upcase_action"]),
            upcase_action_stdin=bool(data["upcase_action_stdin"]),
        )
        c.compiled = [re.compile(p) for p in c.patterns]
        return c


# --------------------------------------------------------------------------- #
# Matching  (pure, unit-testable)
# --------------------------------------------------------------------------- #


@dataclass
class Match:
    row: int          # 0-based line index within the rendered lines
    col: int          # 0-based column (character offset) of the match start
    text: str         # the matched string
    hint: str = ""    # assigned hint label


def find_matches(lines: list[str], patterns: list[re.Pattern]) -> list[Match]:
    """Find non-overlapping matches across `lines`.

    Later matches that overlap an already-claimed span are dropped, so earlier
    (higher-priority) patterns win. Within a line we scan left-to-right; hints
    are later assigned in reverse (bottom-right first) so the closest-to-cursor
    matches get the shortest labels, matching tmux-thumbs.
    """
    out: list[Match] = []
    for row, line in enumerate(lines):
        claimed: list[tuple[int, int]] = []  # (start, end) spans on this line
        spans: list[tuple[int, int, str]] = []
        for pat in patterns:
            for m in pat.finditer(line):
                s, e = m.start(), m.end()
                if s == e:
                    continue
                if any(not (e <= cs or s >= ce) for cs, ce in claimed):
                    continue
                claimed.append((s, e))
                spans.append((s, e, m.group(0)))
        for s, _e, txt in sorted(spans):
            out.append(Match(row=row, col=s, text=txt))
    return out


def gen_hints(n: int, alphabet: str) -> list[str]:
    """Generate `n` hint labels, preferring single chars, then two-char combos.

    Mirrors tmux-thumbs: if everything fits in single chars, use those; else
    reserve enough leading chars as prefixes for two-char hints so no single
    hint is a prefix of a two-char hint (avoids ambiguous input).
    """
    letters = list(alphabet)
    if n <= 0:
        return []
    if n <= len(letters):
        return letters[:n]
    # Need two-char hints. Choose k prefix letters so that
    # (len-k) single hints + k*len two-char hints >= n.
    L = len(letters)
    for k in range(1, L + 1):
        singles = L - k
        capacity = singles + k * L
        if capacity >= n:
            break
    hints: list[str] = list(letters[k:])  # singles come from the tail
    prefixes = letters[:k]
    for p in prefixes:
        for c in letters:
            hints.append(p + c)
            if len(hints) >= n:
                return hints[:n]
    return hints[:n]


def assign_hints(matches: list[Match], alphabet: str) -> list[Match]:
    """Assign hints, closest-to-bottom-right first (shortest labels there)."""
    order = sorted(
        range(len(matches)),
        key=lambda i: (matches[i].row, matches[i].col),
        reverse=True,
    )
    hints = gen_hints(len(matches), alphabet)
    for hint, idx in zip(hints, order):
        matches[idx].hint = hint
    return matches


# --------------------------------------------------------------------------- #
# Pane capture + actions  (side-effecting, injectable for tests)
# --------------------------------------------------------------------------- #


def focused_pane_id() -> str | None:
    """Which herdr pane should we hint?

    The overlay runs in its *own* pane, so HERDR_PANE_ID points at the overlay,
    not the pane we want to scrape. herdr tells us which pane the client was
    focused on when the overlay opened via HERDR_PLUGIN_CONTEXT_JSON — the key
    is ``focused_pane_id`` (verified against herdr 0.7.1). We must NOT fall back
    to HERDR_PANE_ID: that's the overlay itself (empty).
    """
    ctx = os.environ.get("HERDR_PLUGIN_CONTEXT_JSON")
    if ctx:
        try:
            data = json.loads(ctx)
        except Exception:
            data = {}
        # Primary key on herdr 0.7.1.
        pid = data.get("focused_pane_id")
        if isinstance(pid, str) and pid:
            return pid
        # Be liberal about older/newer shapes.
        for key in ("focused_pane", "pane", "focused"):
            v = data.get(key)
            if isinstance(v, dict) and v.get("pane_id"):
                return v["pane_id"]
            if isinstance(v, str) and v:
                return v
        pid = data.get("pane_id")
        if isinstance(pid, str) and pid:
            return pid
    # Last resort only if there's no context at all (e.g. a non-overlay
    # invocation where HERDR_PANE_ID is genuinely the target).
    return os.environ.get("HERDR_PANE_ID")


def herdr_bin() -> str:
    return os.environ.get("HERDR_BIN_PATH", "herdr")


def read_pane(pane_id: str, lines: int = 200) -> list[str]:
    """Capture the visible content of a herdr pane as a list of text lines."""
    out = subprocess.run(
        [herdr_bin(), "pane", "read", pane_id,
         "--source", "visible", "--lines", str(lines), "--format", "text"],
        capture_output=True, text=True,
    )
    return out.stdout.splitlines()


def run_action(argv: list[str], text: str, via_stdin: bool) -> None:
    cmd = [text if a == "{}" else a for a in argv]
    if via_stdin:
        subprocess.run(cmd, input=text, text=True)
    else:
        subprocess.run(cmd)


# --------------------------------------------------------------------------- #
# curses UI
# --------------------------------------------------------------------------- #

# Import curses lazily so the module is importable (for tests) on any platform.


def _run_ui(lines: list[str], matches: list[Match], cfg: Config):
    import curses

    def draw(stdscr, typed: str):
        stdscr.erase()
        max_y, max_x = stdscr.getmaxyx()
        # base snapshot, dimmed
        for r, line in enumerate(lines[: max_y - 1]):
            try:
                stdscr.addnstr(r, 0, line, max_x - 1, curses.A_DIM)
            except curses.error:
                pass
        # hint labels
        for m in matches:
            if m.row >= max_y - 1:
                continue
            hint = m.hint
            # Filter by what's been typed so far (progressive narrowing).
            if typed and not hint.startswith(typed):
                attr = curses.A_DIM
                shown = hint
            else:
                attr = curses.color_pair(1) | curses.A_BOLD
                shown = hint
            try:
                stdscr.addnstr(m.row, m.col, shown, max(0, max_x - 1 - m.col), attr)
                # highlight the remaining match text after the hint
                rest_col = m.col + len(shown)
                rest = m.text[len(shown):] if len(m.text) > len(shown) else ""
                if rest and rest_col < max_x - 1:
                    stdscr.addnstr(m.row, rest_col, rest,
                                   max_x - 1 - rest_col, curses.A_UNDERLINE)
            except curses.error:
                pass
        footer = " thumbs: type a hint · lower=copy UPPER=open · esc/q=cancel "
        try:
            stdscr.addnstr(max_y - 1, 0, footer.ljust(max_x - 1),
                           max_x - 1, curses.A_REVERSE)
        except curses.error:
            pass
        stdscr.refresh()

    def main(stdscr):
        curses.curs_set(0)
        curses.use_default_colors()
        try:
            curses.init_pair(1, curses.COLOR_YELLOW, -1)
        except curses.error:
            pass
        by_hint = {m.hint: m for m in matches}
        by_hint_lower = {m.hint.lower(): m for m in matches}
        typed = ""
        while True:
            draw(stdscr, typed)
            try:
                ch = stdscr.get_wch()
            except curses.error:
                continue
            if ch in ("\x1b", "\x03"):  # esc / ctrl-c
                return None
            if isinstance(ch, str) and ch in ("q", "Q") and not typed:
                # allow q as cancel only when no hint starts with q
                if not any(h.startswith("q") for h in by_hint):
                    return None
            if not isinstance(ch, str):
                continue
            is_upper = ch.isupper()
            typed += ch.lower()
            # exact single/two-char match?
            if typed in by_hint_lower:
                return (by_hint_lower[typed], is_upper)
            # dead end — reset
            if not any(h.startswith(typed) for h in by_hint_lower):
                typed = ""

    return curses.wrapper(main)


# --------------------------------------------------------------------------- #
# Entrypoint
# --------------------------------------------------------------------------- #


def _debug_dump() -> None:
    """Write env + resolved pane to a file for headless debugging."""
    path = os.environ.get("THUMBS_DEBUG")
    if not path:
        return
    try:
        pane = focused_pane_id()
        info = {
            "context_json": os.environ.get("HERDR_PLUGIN_CONTEXT_JSON"),
            "HERDR_PANE_ID": os.environ.get("HERDR_PANE_ID"),
            "HERDR_WORKSPACE_ID": os.environ.get("HERDR_WORKSPACE_ID"),
            "resolved_pane": pane,
            "pane_lines": read_pane(pane) if pane else None,
        }
        Path(path).write_text(json.dumps(info, indent=2))
    except Exception as e:  # pragma: no cover
        Path(path).write_text(f"debug error: {e!r}")


def main() -> int:
    cfg = Config.load()
    _debug_dump()

    # Allow feeding pane text on stdin for headless testing / piping.
    if not sys.stdin.isatty() and os.environ.get("THUMBS_STDIN") == "1":
        lines = sys.stdin.read().splitlines()
    else:
        pane = focused_pane_id()
        if not pane:
            print("herdr-thumbs: no focused pane in context", file=sys.stderr)
            return 2
        lines = read_pane(pane)

    matches = find_matches(lines, cfg.compiled)
    if not matches:
        return 0
    matches = assign_hints(matches, cfg.alphabet)

    # Headless drive hook for end-to-end testing inside a real overlay: set
    # THUMBS_AUTO=<hint> (upper-case for the open action) to skip the UI and
    # act on that hint directly. Never set in normal use.
    auto = os.environ.get("THUMBS_AUTO")
    if auto:
        upper = auto.isupper()
        want = auto.lower()
        for m in matches:
            if m.hint == want:
                if upper:
                    run_action(cfg.upcase_action, m.text, cfg.upcase_action_stdin)
                else:
                    run_action(cfg.default_action, m.text, cfg.default_action_stdin)
                return 0
        print(f"herdr-thumbs: THUMBS_AUTO hint {auto!r} not found", file=sys.stderr)
        return 3

    result = _run_ui(lines, matches, cfg)
    if result is None:
        return 0
    match, upper = result
    if upper:
        run_action(cfg.upcase_action, match.text, cfg.upcase_action_stdin)
    else:
        run_action(cfg.default_action, match.text, cfg.default_action_stdin)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
