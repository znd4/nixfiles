#!/usr/bin/env bash
# hunk-mr — review a GitLab MR / GitHub PR in Hunk and round-trip review notes
# back to the forge as inline diff comments.
#
# Run it from inside a checkout/worktree of the MR/PR's source branch (e.g. the
# review worktrees created by `tmux-mr-review`). All forge context is derived
# from `origin` and the remote branch pointing at HEAD — nothing is persisted.
#
# Subcommands:
#   hunk-mr open                Open the MR/PR diff in Hunk (target...HEAD)
#   hunk-mr pull [options]      Import the MR/PR's review threads into Hunk as notes
#   hunk-mr push [options]      Publish your Hunk review notes as MR/PR comments
#   hunk-mr info                Print the forge context derived from this checkout
#
# pull options:
#   --all                       Include resolved threads (default: unresolved only)
#   --number <n>                Override the MR/PR number
#
# push options:
#   --type <user|agent|ai|all>  Which Hunk notes to publish (default: user)
#   --post                      Actually publish (default: dry-run preview)
#   --number <n>                Override the MR/PR number
#   --yes, -y                   Skip the confirmation prompt
#
# Hunk's comments live only in the running TUI session, so both `pull` and `push`
# must run while the Hunk window for this checkout is open (`hunk-mr open`).
#
# pull / push separation: imported review threads land in Hunk's agent/live note
# bucket (CLI-inserted) and carry a "↩" rationale footer, so `push` — which only
# harvests your own `user` notes by default — never echoes other people's
# comments back to the forge, even with `--type all`.

set -euo pipefail

die() { printf 'hunk-mr: %s\n' "$*" >&2; exit 1; }

# Globals populated by the derive_* helpers below.
forge="" host="" project="" branch=""
number="" target="" base="" head="" start=""

# Derive forge / host / project / branch from the git remote and HEAD.
derive_remote() {
  local origin
  origin=$(git remote get-url origin 2>/dev/null) \
    || die "not in a git repo with an 'origin' remote"

  if [[ $origin =~ ^git@([^:]+):(.+)$ ]]; then
    host=${BASH_REMATCH[1]}
    project=${BASH_REMATCH[2]}
  elif [[ $origin =~ ^(ssh|https?)://([^/]+)/(.+)$ ]]; then
    host=${BASH_REMATCH[2]}
    project=${BASH_REMATCH[3]}
  else
    die "could not parse origin URL: $origin"
  fi
  host=${host#*@}        # strip a possible user@ from ssh:// URLs
  project=${project%.git}

  if [[ $host == github.com ]]; then forge=github; else forge=gitlab; fi

  # Review worktrees are checked out detached, so recover the source branch
  # from the remote ref(s) that point at HEAD.
  branch=$(git for-each-ref --points-at HEAD --format='%(refname:lstrip=3)' \
            refs/remotes/origin 2>/dev/null | grep -vx 'HEAD' | head -n1 || true)
}

# Resolve the open MR/PR number for the current branch.
resolve_number() {
  [[ -z $number ]] || return 0
  [[ -n $branch ]] || die "could not determine the source branch; pass --number"
  if [[ $forge == github ]]; then
    number=$(gh pr list --repo "$project" --head "$branch" --state open \
              --json number --jq '.[0].number // empty')
  else
    local enc
    enc=$(jq -rn --arg p "$project" '$p|@uri')
    number=$(glab api --hostname "$host" \
      "projects/$enc/merge_requests?source_branch=$branch&state=opened" \
      | jq -r '.[0].iid // empty')
  fi
  [[ -n $number ]] || die "no open MR/PR found for branch '$branch' (pass --number)"
}

# Resolve target branch and the base/head/start SHAs the forge diff APIs need.
resolve_diffrefs() {
  if [[ $forge == github ]]; then
    local j
    j=$(gh pr view "$number" --repo "$project" \
          --json baseRefName,baseRefOid,headRefOid)
    target=$(jq -r .baseRefName <<<"$j")
    base=$(jq -r .baseRefOid <<<"$j")
    head=$(jq -r .headRefOid <<<"$j")
    start=$base
  else
    local enc j
    enc=$(jq -rn --arg p "$project" '$p|@uri')
    j=$(glab api --hostname "$host" "projects/$enc/merge_requests/$number")
    target=$(jq -r .target_branch <<<"$j")
    base=$(jq -r .diff_refs.base_sha <<<"$j")
    head=$(jq -r .diff_refs.head_sha <<<"$j")
    start=$(jq -r .diff_refs.start_sha <<<"$j")
  fi
}

cmd_open() {
  derive_remote
  resolve_number
  resolve_diffrefs
  git fetch -q origin "$target" 2>/dev/null || true
  # `target...HEAD` shows what the MR/PR introduces; the new-side line numbers
  # match the forge's file line numbers, so notes map cleanly onto comments.
  exec hunk diff "origin/$target...HEAD" "$@"
}

post_gitlab() {
  local path=$1 nl=$2 ol=$3 body=$4 enc payload
  enc=$(jq -rn --arg p "$project" '$p|@uri')
  payload=$(jq -n \
    --arg body "$body" --arg base "$base" --arg head "$head" --arg start "$start" \
    --arg path "$path" --arg nl "$nl" --arg ol "$ol" '
    {
      body: $body,
      position: ({
        position_type: "text",
        base_sha: $base, head_sha: $head, start_sha: $start,
        new_path: $path, old_path: $path
      } + (if $nl != "" then { new_line: ($nl|tonumber) }
                        else { old_line: ($ol|tonumber) } end))
    }')
  printf '%s' "$payload" | glab api --hostname "$host" --method POST \
    "projects/$enc/merge_requests/$number/discussions" --input - >/dev/null
}

post_github() {
  local path=$1 nl=$2 ol=$3 body=$4 line side
  if [[ -n $nl ]]; then line=$nl; side=RIGHT; else line=$ol; side=LEFT; fi
  gh api --method POST "repos/$project/pulls/$number/comments" \
    -f body="$body" -f commit_id="$head" -f path="$path" \
    -F line="$line" -f side="$side" >/dev/null
}

cmd_push() {
  local type=user post=0 yes=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --type)    type=$2; shift 2 ;;
      --post)    post=1; shift ;;
      --dry-run) post=0; shift ;;
      --yes|-y)  yes=1; shift ;;
      --number)  number=$2; shift 2 ;;
      *)         die "unknown option: $1" ;;
    esac
  done

  derive_remote
  resolve_number
  resolve_diffrefs

  local raw notes count
  raw=$(hunk session comment list --repo . --type "$type" --json) \
    || die "could not read Hunk notes — is a Hunk session open in this checkout?"

  # Normalize defensively: the exact field names in `comment list --json` may
  # vary by Hunk version, so accept the common aliases. Adjust here if needed.
  notes=$(jq -c '
    (if type=="array" then . else (.comments // .notes // .data // []) end)
    | map({
        path:      (.filePath // .file // .path // ""),
        newLine:   (.newLine // .new_line // null),
        oldLine:   (.oldLine // .old_line // null),
        summary:   (.summary // .body // .text // ""),
        rationale: (.rationale // "")
      })
    | map(select(.path != "" and (.newLine != null or .oldLine != null)))
    | map(select((.rationale | startswith("↩")) | not))
  ' <<<"$raw")

  count=$(jq 'length' <<<"$notes")
  [[ $count -gt 0 ]] || { echo "No publishable '$type' notes found."; exit 0; }

  local kind; kind=$([[ $forge == github ]] && echo PR || echo MR)
  printf '\n%s #%s on %s/%s — %s note(s) to publish:\n\n' \
    "$kind" "$number" "$host" "$project" "$count"
  jq -r '.[] | "  \(.path):\(.newLine // .oldLine)\n    \(.summary)" +
              (if .rationale != "" then "\n    " + .rationale else "" end) + "\n"' \
    <<<"$notes"

  if [[ $post -eq 0 ]]; then
    echo "(dry-run — re-run with --post to publish)"
    exit 0
  fi

  if [[ $yes -eq 0 ]]; then
    gum confirm "Publish $count comment(s) to $host/$project #$number?" \
      || { echo "Aborted."; exit 1; }
  fi

  local i path nl ol summary rationale body
  for ((i = 0; i < count; i++)); do
    path=$(jq -r ".[$i].path" <<<"$notes")
    nl=$(jq -r ".[$i].newLine // empty" <<<"$notes")
    ol=$(jq -r ".[$i].oldLine // empty" <<<"$notes")
    summary=$(jq -r ".[$i].summary" <<<"$notes")
    rationale=$(jq -r ".[$i].rationale" <<<"$notes")

    body=$summary
    [[ -n $rationale ]] && body=$(printf '%s\n\n%s' "$summary" "$rationale")
    body=$(printf '%s\n\n— via hunk-mr' "$body")

    if [[ $forge == github ]]; then
      post_github "$path" "$nl" "$ol" "$body"
    else
      post_gitlab "$path" "$nl" "$ol" "$body"
    fi
    echo "  ✓ $path:${nl:-$ol}"
  done
}

# Emit a normalized JSON array of inline review comments for the current MR/PR:
#   [{ path, side: "new"|"old", line, author, body, url }]
# One element per individual comment (replies included). $1 = include-resolved (0/1).
fetch_comments() {
  local all=$1
  if [[ $forge == github ]]; then
    local owner=${project%%/*} repo=${project##*/}
    # $owner/$repo/$num below are GraphQL variables, not shell expansions.
    # shellcheck disable=SC2016
    gh api graphql -F owner="$owner" -F repo="$repo" -F num="$number" -f query='
      query($owner:String!,$repo:String!,$num:Int!){
        repository(owner:$owner,name:$repo){
          pullRequest(number:$num){
            reviewThreads(first:100){ nodes{
              isResolved
              comments(first:100){ nodes{
                author{login} body path line originalLine diffSide url
              } }
            } }
          }
        }
      }' --jq "
      [ .data.repository.pullRequest.reviewThreads.nodes[]
        | select($all == 1 or (.isResolved | not))
        | .comments.nodes[]
        | { path: .path,
            side: (if .diffSide == \"LEFT\" then \"old\" else \"new\" end),
            line: (.line // .originalLine),
            author: (.author.login // \"reviewer\"),
            body: .body,
            url: .url }
        | select(.line != null) ]"
  else
    local enc
    enc=$(jq -rn --arg p "$project" '$p|@uri')
    glab api --hostname "$host" \
      "projects/$enc/merge_requests/$number/discussions?per_page=100" \
      | jq -c --argjson all "$all" \
             --arg host "$host" --arg project "$project" --arg num "$number" '
      [ .[] | .notes[]
        | select(.system == false)
        | select(.position != null and .position.position_type == "text")
        | select($all == 1 or (.resolved != true))
        | { path: (.position.new_path // .position.old_path),
            side: (if .position.new_line != null then "new" else "old" end),
            line: (.position.new_line // .position.old_line),
            author: (.author.name // .author.username // "reviewer"),
            body: .body,
            url: ("https://" + $host + "/" + $project +
                  "/-/merge_requests/" + $num + "#note_" + (.id|tostring)) }
        | select(.line != null) ]'
  fi
}

cmd_pull() {
  local all=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --all)    all=1; shift ;;
      --number) number=$2; shift 2 ;;
      *)        die "unknown option: $1" ;;
    esac
  done

  derive_remote
  resolve_number

  # Make sure a Hunk session is actually open for this checkout before importing.
  hunk session get --repo . >/dev/null 2>&1 \
    || die "no Hunk session open in this checkout — run 'hunk-mr open' first"

  local items count
  items=$(fetch_comments "$all") || die "could not fetch review threads from the forge"
  count=$(jq 'length' <<<"$items")
  [[ $count -gt 0 ]] || { echo "No matching review comments to import."; exit 0; }

  echo "Importing $count comment(s) into the Hunk session…"
  local i path side line author body url lineflag added=0 skipped=0
  for ((i = 0; i < count; i++)); do
    path=$(jq -r ".[$i].path" <<<"$items")
    side=$(jq -r ".[$i].side" <<<"$items")
    line=$(jq -r ".[$i].line" <<<"$items")
    author=$(jq -r ".[$i].author" <<<"$items")
    body=$(jq -r ".[$i].body" <<<"$items")
    url=$(jq -r ".[$i].url" <<<"$items")
    [[ $side == old ]] && lineflag=--old-line || lineflag=--new-line

    if hunk session comment add --repo . --file "$path" "$lineflag" "$line" \
         --author "$author" --summary "$body" --rationale "↩ $url" >/dev/null 2>&1; then
      echo "  + $path:$line ($author)"
      added=$((added + 1))
    else
      echo "  ! skipped $path:$line ($author) — line not in the loaded diff"
      skipped=$((skipped + 1))
    fi
  done
  printf 'Imported %s, skipped %s.\n' "$added" "$skipped"
}

cmd_info() {
  derive_remote
  resolve_number
  resolve_diffrefs
  cat <<EOF
forge:   $forge
host:    $host
project: $project
branch:  $branch
number:  $number
target:  $target
base:    $base
head:    $head
start:   $start
EOF
}

usage() {
  cat <<'EOF'
hunk-mr — review a GitLab MR / GitHub PR in Hunk and round-trip notes as comments.
Run from inside a checkout/worktree of the MR/PR's source branch.

  hunk-mr open                Open the MR/PR diff in Hunk (target...HEAD)
  hunk-mr pull [options]      Import the MR/PR's review threads into Hunk as notes
  hunk-mr push [options]      Publish your Hunk review notes as MR/PR comments
  hunk-mr info                Print the forge context derived from this checkout

pull options:
  --all                       Include resolved threads (default: unresolved only)
  --number <n>                Override the MR/PR number

push options:
  --type <user|agent|ai|all>  Which Hunk notes to publish (default: user)
  --post                      Actually publish (default: dry-run preview)
  --number <n>                Override the MR/PR number
  --yes, -y                   Skip the confirmation prompt

`pull` and `push` both read/write the running Hunk session, so keep its window
open. Imported notes carry a "↩" footer and are never re-published by `push`.
EOF
}

main() {
  local cmd=${1:-help}
  shift || true
  case $cmd in
    open)        cmd_open "$@" ;;
    pull)        cmd_pull "$@" ;;
    push|sync)   cmd_push "$@" ;;
    info)        cmd_info "$@" ;;
    help|-h|--help) usage ;;
    *)           die "unknown subcommand '$cmd' (try: open, pull, push, info)" ;;
  esac
}

main "$@"
