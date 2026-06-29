#!/usr/bin/env bash
# tmux-mr-review — paste a GitHub PR / GitLab MR URL into a popup, check it out,
# and drop into a dedicated tmux session laid out for reviewing it in Hunk.
#
# Flow:
#   1. gum popup prompts for a PR/MR URL.
#   2. The repo is cloned (once) under $HUNK_MR_WORKDIR/<host>/<project> and the
#      PR/MR head is fetched into a detached worktree.
#   3. A tmux session is created with two panes — a terminal (left) and Hunk
#      auto-refreshing the PR/MR diff (right) — and the client is switched to it.
#
# Design notes:
#   * API-free checkout. We fetch the forge's well-known refs (GitHub
#     refs/pull/N/head, GitLab refs/merge-requests/N/head) over SSH, so this
#     needs no gh/glab auth. Auth-requiring comment sync (`hunk-mr pull`) is a
#     separate step, run from the terminal pane.
#   * The terminal pane is stamped with HUNK_MR_* env vars identifying the PR/MR,
#     so `hunk-mr pull` invoked there knows what to sync without re-deriving it.
#   * Idempotent: re-running for the same PR/MR just switches to the existing
#     session (and refreshes the worktree to the latest head).
#
# $HUNK_MR_WORKDIR (clone root, default ~/Work) is exported by the Nix wrapper.

set -euo pipefail

# Print an error and linger briefly: `display-popup -E` closes the moment this
# script exits, so without the sleep the message would flash past unread.
die() { printf '\n%s\n' "$*" >&2; sleep 3; exit 1; }

work_root="${HUNK_MR_WORKDIR:-$HOME/Work}"
work_root="${work_root/#\~/$HOME}"   # expand a leading ~ ourselves (no shell glob here)

raw=$(gum input \
  --header "Review a GitHub PR / GitLab MR in Hunk" \
  --prompt "❯ " \
  --placeholder "github.com/o/r/pull/N   •   gitlab.…/-/merge_requests/N")
[ -z "$raw" ] && exit 0   # empty input / Esc → user cancelled

# Extract the URL rather than trusting the raw field verbatim. Inside a tmux
# popup, `set -g allow-passthrough on` lets the terminal's responses to Hunk's
# capability probes leak into whatever is reading stdin — e.g. a stray "P" from a
# DCS reply, or "Gi=…;OK" from a Kitty graphics query. Grepping out just the URL
# means those bytes can't corrupt the value we parse.
url=$(printf '%s' "$raw" | grep -oiE 'https?://[^[:space:]]+' | head -n1 || true)
[ -z "$url" ] && die "No URL found in input:
  $raw"

# From here on it's the non-interactive checkout + tmux work — where failures
# lurk and the popup swallows output — so tee everything to a per-invocation log.
# Deliberately started *after* the gum prompt: redirecting stdout to a pipe
# before gum runs makes gum render in a degraded (ugly) non-tty mode.
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-mr-review"
mkdir -p "$log_dir"
exec > >(tee -a "$log_dir/$(date +%Y%m%dT%H%M%S)-$$.log") 2>&1
printf '=== tmux-mr-review %s :: %s ===\n' "$(date)" "$url"

# --- parse the URL -----------------------------------------------------------
# GitHub:  https://github.com/<owner>/<repo>/pull/<n>
# GitLab:  https://<host>/<group>/[<subgroups>/]<project>/-/merge_requests/<n>
# The GitLab `project` capture is greedy up to `/-/merge_requests/`, so nested
# groups (group/sub/project) are preserved.
if [[ $url =~ ^https://github\.com/([^/]+/[^/]+)/pull/([0-9]+) ]]; then
  forge=github
  host=github.com
  project=${BASH_REMATCH[1]}
  number=${BASH_REMATCH[2]}
  head_ref="refs/pull/$number/head"
elif [[ $url =~ ^https://([^/]+)/(.+)/-/merge_requests/([0-9]+) ]]; then
  forge=gitlab
  host=${BASH_REMATCH[1]}
  project=${BASH_REMATCH[2]}
  number=${BASH_REMATCH[3]}
  head_ref="refs/merge-requests/$number/head"
else
  die "Not a recognized GitHub PR or GitLab MR URL:
  $url"
fi
project=${project%.git}   # tolerate a pasted ….git URL

repo_dir="$work_root/$host/$project"

# --- clone the repo if we don't have it yet (SSH, no forge API) --------------
if [ ! -e "$repo_dir/.git" ]; then
  mkdir -p "$(dirname "$repo_dir")"
  git clone "git@$host:$project.git" "$repo_dir" || die "clone failed: git@$host:$project.git"
fi

# --- base branch for the review diff (API-free) ------------------------------
# We diff the PR/MR head against the repo's default branch. origin/HEAD records
# it after clone; if it's somehow unset, ask the remote (set-head --auto) and
# fall back to origin/main.
base=$(git -C "$repo_dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
if [ -z "$base" ]; then
  git -C "$repo_dir" remote set-head origin --auto >/dev/null 2>&1 || true
  base=$(git -C "$repo_dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
fi

# --- fetch the PR/MR head and place a worktree at it -------------------------
# Force-fetch (`+`) the forge head ref into a private local ref so re-runs pick
# up new pushes. The worktree is detached (the head isn't a normal branch), which
# also sidesteps "branch already checked out in another worktree" conflicts.
local_ref="refs/review/$forge-$number"
git -C "$repo_dir" fetch -q origin "+$head_ref:$local_ref" \
  || die "could not fetch $head_ref — is the URL right / do you have access?"
head_sha=$(git -C "$repo_dir" rev-parse "$local_ref")

worktree_dir="$repo_dir/.zn-work/$forge-$number"
if [ -d "$worktree_dir" ]; then
  git -C "$worktree_dir" checkout -q --detach "$head_sha" 2>/dev/null || true   # refresh existing
else
  mkdir -p "$repo_dir/.zn-work"
  git -C "$repo_dir" worktree add -q --detach "$worktree_dir" "$head_sha" \
    || die "could not create worktree at $worktree_dir"
fi

# --- tmux session ------------------------------------------------------------
repo_name=$(basename "$project")
session="review/$repo_name/$forge-$number"
session=${session//[.:]/-}   # tmux treats ':' and '.' as target separators — strip them

# Capture the client that launched this popup so we can switch it *explicitly*;
# an implicit `switch-client` from inside a popup doesn't reliably target it.
client=$(tmux display-message -p '#{client_name}' 2>/dev/null || true)

focus_session() {
  if [ -n "$client" ]; then
    tmux switch-client -c "$client" -t "=$session"   # '=' forces an exact session-name match
  elif [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "=$session"
  else
    tmux attach -t "=$session"   # not run from inside tmux (e.g. manual invocation)
  fi
}

# Already open → just go to it (idempotent re-run).
if tmux has-session -t "=$session" 2>/dev/null; then
  focus_session
  exit 0
fi

# Stamp both panes (session env is inherited by every pane) so `hunk-mr pull`
# run from the terminal knows which PR/MR + base this session is reviewing.
env_args=(
  -e "HUNK_MR_URL=$url"
  -e "HUNK_MR_FORGE=$forge"
  -e "HUNK_MR_HOST=$host"
  -e "HUNK_MR_PROJECT=$project"
  -e "HUNK_MR_NUMBER=$number"
  -e "HUNK_MR_BASE=$base"
)

# Pane 0 (left, ~38%): plain terminal.
# NB: `=$session` is a *session* target and won't resolve as a *pane* target for
# split-window ("can't find pane"), so we capture the new pane's id from -P and
# split that instead.
pane0=$(tmux new-session -d -P -F '#{pane_id}' -s "$session" -c "$worktree_dir" \
  "${env_args[@]}")

# Pane 1 (right, ~62%): Hunk auto-refreshing the PR/MR diff (`base...HEAD` shows
# what the branch adds), dropping to a shell if you quit it. Created last and
# left focused on purpose: Hunk probes the terminal for graphics support on
# startup, and keeping focus here means it consumes its own reply instead of the
# reply leaking into the terminal pane's prompt (the "Gi=…;OK" noise).
# shellcheck disable=SC2016  # the single-quoted $base...HEAD is for fish, not bash
hunk_cmd='hunk diff '"'$base...HEAD'"' --watch; exec fish'
tmux split-window -h -l 62% -t "$pane0" -c "$worktree_dir" "${env_args[@]}" \
  fish -c "$hunk_cmd"

focus_session
