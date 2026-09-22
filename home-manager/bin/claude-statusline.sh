#!/usr/bin/env bash
# Claude Code status line.
#
# Line 1: session context (model, directory, branch, context-window %).
# Line 2: the ask queue -- shown only when non-empty. Items that need the
# user's personal action. This row cannot scroll away.
#
# Reads note files with awk instead of calling `ask-zk count`, to avoid uv
# start-up on every assistant message: CLI ~123 ms, awk ~62 ms.
#
# Does not read zk's index database (~32 ms). The index only updates when
# `zk index` runs; ticking a checkbox in Obsidian does not trigger it. The
# count would go stale for exactly the action it tracks. Files are the only
# always-correct source.
#
# Measured 2026-09-15 at 330 notes. Previous SQLite store read: ~40 ms.

set -uo pipefail

input="$(cat)"
# The Nix wrapper sets ASK_NOTEBOOK from `programs.ask-zk.notebook`, so this
# script and `ask-zk` always read the same notebook.
NOTES="${ASK_NOTEBOOK:-$HOME/notes}"

esc() { printf '\033[%sm' "$1"; }
R="$(esc 0)"; DIM="$(esc 2)"; BOLD="$(esc 1)"
CYAN="$(esc 36)"; GREEN="$(esc 32)"; YELLOW="$(esc 33)"; RED="$(esc 31)"

# ---- line 1: ordinary session context ---------------------------------------
# Split on TAB, not whitespace: every current model display name contains a
# space ("Opus 5"), and word-splitting put it in two fields, which shifted the
# directory into DIR and left PCT non-numeric.
IFS=$'\t' read -r MODEL DIR PCT <<<"$(
  printf '%s' "$input" | jq -r '
    [ (.model.display_name // "?"),
      (.workspace.current_dir // .cwd // "?" | split("/") | last),
      ((.context_window.used_percentage // 0) | floor | tostring)
    ] | @tsv'
)"

BRANCH="$(git -C "$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // "."')" \
  rev-parse --abbrev-ref HEAD 2>/dev/null)"

line1="${DIM}${MODEL}${R} ${CYAN}${DIR}${R}"
[ -n "$BRANCH" ] && line1+=" ${DIM}(${BRANCH})${R}"
if   [ "$PCT" -ge 80 ] 2>/dev/null; then line1+=" ${RED}${PCT}% ctx${R}"
elif [ "$PCT" -ge 50 ] 2>/dev/null; then line1+=" ${YELLOW}${PCT}% ctx${R}"
else                                     line1+=" ${DIM}${PCT}% ctx${R}"; fi
printf '%b\n' "$line1"

# ---- line 2: the ask queue (only when non-empty) ----------------------------
[ -d "$NOTES/.zk" ] || exit 0

# ISO-8601 UTC strings sort chronologically, so staleness is a string compare
# against a precomputed cutoff. No date arithmetic needed in awk.
#
# Tries GNU `date -d` first, then BSD `date -v`. The Nix wrapper puts GNU
# coreutils ahead of /usr/bin on PATH; an unwrapped run on macOS reaches the
# BSD date. Failure is silent: an empty CUTOFF makes every compare false, so
# the badge never turns red.
DAYS="${ASK_STALE_DAYS:-7}"
CUTOFF="$(date -u -d "-${DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"

# An item is one note with both `#ask` and an unchecked box. The checkbox is
# the only state — no status tag, nothing in the frontmatter.
#
# `nextfile` stops at the checkbox and the FNR > 30 cap stops at the head of
# the file, so this reads ~30 lines per note, not all of them. Both guards
# assume the checkbox and `created:` sit near the top, which is where the
# note template puts them. A note that buries its checkbox below line 30
# will not be counted.
read -r OPEN STALE <<<"$(
  awk -v cutoff="$CUTOFF" '
    FILENAME != prev {
      if (prev != "" && open) { o++; if (created != "" && created < cutoff) s++ }
      prev = FILENAME; created = ""; open = 0
    }
    FNR > 30 { nextfile }
    /^created: / { created = $2 }
    /^- \[ \] / && /#ask/ { open = 1; nextfile }
    END {
      if (open) { o++; if (created != "" && created < cutoff) s++ }
      print o+0, s+0
    }
  ' "$NOTES"/*.md 2>/dev/null
)"

[ "${OPEN:-0}" -gt 0 ] 2>/dev/null || exit 0

word="asks"; [ "$OPEN" -eq 1 ] && word="ask"

# No cap on queue size. Staleness is the only escalation: when any open item
# exceeds ASK_STALE_DAYS the whole badge turns red. Red means "surface the
# queue in the first message of the session" (see ~/.claude/skills/ask-zk/
# SKILL.md).
if [ "${STALE:-0}" -gt 0 ] 2>/dev/null; then
  badge="${BOLD}${RED}▲ ${OPEN} ${word} waiting on you (${STALE} stale)${R}"
else
  badge="${BOLD}${YELLOW}▲ ${OPEN} ${word} waiting on you${R}"
fi
printf '%b\n' "${badge}   ${DIM}run:${R} ${GREEN}ask-zk${R}"
