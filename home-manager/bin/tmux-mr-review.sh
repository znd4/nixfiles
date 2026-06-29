#!/usr/bin/env bash
# tmux-mr-review — paste a GitHub PR / GitLab MR URL into a popup, check it out,
# and drop into a dedicated tmux session laid out for reviewing it in Hunk.
#
# Flow:
#   1. gum popup prompts for a PR/MR URL.
#   2. The repo is cloned (once) under $HUNK_MR_WORKDIR/<host>/<project> and the
#      PR/MR source is checked out as a real local branch (pr-N / mr-N) in a
#      worktree, tracking the contributor's source (the fork remote for
#      cross-repo PRs/MRs).
#   3. A tmux session is created with two panes — a terminal (left) and Hunk
#      auto-refreshing the PR/MR diff (right) — and the client is switched to it.
#
# Design notes:
#   * Checkout resolves the source remote + branch via the forge API (gh/glab,
#     already needed by `hunk-mr pull`) so the worktree is on a named branch
#     rather than a detached head — `git status`/Hunk show the branch and updates
#     can be pulled. If the API is unavailable it falls back to the forge head
#     ref (GitHub refs/pull/N/head, GitLab refs/merge-requests/N/head) over SSH.
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

# --- resolve the source remote + branch via the forge API -------------------
# We check out a real local branch (pr-N / mr-N) tracking the PR/MR's source,
# rather than a detached head, so `git status`/Hunk show a branch and updates
# can be pulled. For cross-repo (fork) PRs/MRs the source lives on the fork, so
# we add it as a remote named after the fork owner. This needs gh/glab (already
# required by `hunk-mr pull`); the forge head ref remains the fallback below.
if [ "$forge" = github ]; then
  review_branch="pr-$number"
else
  review_branch="mr-$number"
fi

source_remote=origin
source_branch=""
fork_url=""

if [ "$forge" = github ]; then
  if mr_json=$(gh pr view "$number" --repo "$project" \
        --json headRefName,headRepositoryOwner,headRepository,isCrossRepository 2>/dev/null); then
    source_branch=$(printf '%s' "$mr_json" | jq -r '.headRefName')
    if [ "$(printf '%s' "$mr_json" | jq -r '.isCrossRepository')" = true ]; then
      fork_owner=$(printf '%s' "$mr_json" | jq -r '.headRepositoryOwner.login')
      fork_repo=$(printf '%s' "$mr_json" | jq -r '.headRepository.name')
      source_remote="$fork_owner"
      fork_url="git@$host:$fork_owner/$fork_repo.git"
    fi
  fi
else
  if mr_json=$(glab mr view "$number" --repo "$project" --output json 2>/dev/null); then
    source_branch=$(printf '%s' "$mr_json" | jq -r '.source_branch')
    src_pid=$(printf '%s' "$mr_json" | jq -r '.source_project_id')
    tgt_pid=$(printf '%s' "$mr_json" | jq -r '.target_project_id')
    if [ -n "$src_pid" ] && [ "$src_pid" != "$tgt_pid" ] && [ "$src_pid" != null ]; then
      if proj_json=$(glab api "projects/$src_pid" 2>/dev/null); then
        source_remote=$(printf '%s' "$proj_json" | jq -r '.path_with_namespace' | tr '/' '-')
        fork_url=$(printf '%s' "$proj_json" | jq -r '.ssh_url_to_repo')
      fi
    fi
  fi
fi

worktree_dir="$repo_dir/.zn-work/$forge-$number"

if [ -n "$source_branch" ] && [ "$source_branch" != null ]; then
  # Add the fork remote (idempotent) for cross-repo sources.
  if [ "$source_remote" != origin ] && [ -n "$fork_url" ]; then
    if ! git -C "$repo_dir" remote get-url "$source_remote" >/dev/null 2>&1; then
      git -C "$repo_dir" remote add "$source_remote" "$fork_url"
    fi
  fi
  # Fetch the source branch and point the review branch at it.
  git -C "$repo_dir" fetch -q "$source_remote" \
      "+refs/heads/$source_branch:refs/remotes/$source_remote/$source_branch" \
    || die "could not fetch $source_branch from $source_remote"
  start_point="$source_remote/$source_branch"
else
  # API unavailable — fall back to the forge head ref (detached-equivalent, but
  # we still create a local branch so Hunk shows a name).
  git -C "$repo_dir" fetch -q origin "+$head_ref:refs/review/$forge-$number" \
    || die "could not fetch $head_ref — is the URL right / do you have access?"
  start_point="refs/review/$forge-$number"
fi

# Create/refresh the worktree on the review branch.
if [ -d "$worktree_dir" ]; then
  git -C "$worktree_dir" checkout -q -B "$review_branch" "$start_point" 2>/dev/null || true
else
  mkdir -p "$repo_dir/.zn-work"
  git -C "$repo_dir" worktree add -q -B "$review_branch" "$worktree_dir" "$start_point" \
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
