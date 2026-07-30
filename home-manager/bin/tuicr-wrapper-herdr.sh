# Launch tuicr in a herdr split pane, the way upstream's tuicr-wrapper.sh does
# for tmux and tuicr-wrapper-zellij.sh does for zellij.
#
# herdr equivalents of the tmux primitives upstream relies on:
#   tmux split-window -P -F '#{pane_id}'  ->  herdr pane split  (.result.pane.pane_id)
#   tmux split-window '<cmd>'             ->  herdr pane run <pane> <cmd>
#   tmux wait-for -S / tmux wait-for      ->  a sentinel line + herdr wait output --match
#   tmux list-panes -F pane_current_cmd   ->  herdr pane process-info --pane <id>
#   tmux kill-pane                        ->  herdr pane close <pane>
#
# `herdr` is deliberately NOT pinned in runtimeInputs: this script only ever runs
# inside a herdr session, so herdr is on PATH by definition, and pinning it here
# would name a binary that is already there. Same reasoning as `hunk` in
# ../programs/hunk-mr.nix.

TUICR_PANE_DIRECTION="${TUICR_PANE_DIRECTION:-right}"   # right (side-by-side) or down
TUICR_PANE_RATIO="${TUICR_PANE_RATIO:-0.5}"             # passed to `herdr pane split --ratio`
TUICR_TIMEOUT_SECONDS="${TUICR_TIMEOUT_SECONDS:-3600}"  # give up waiting after this long

# Opening the pane unfocused is the default on purpose. This wrapper is
# normally called by an agent, and `herdr pane split --focus` yanks the
# keyboard away from whatever the human was typing into mid-keystroke. The
# pane is still created and visible; the user moves to it when they are ready.
# Opt back in with --focus or TUICR_PANE_FOCUS=1.
TUICR_PANE_FOCUS="${TUICR_PANE_FOCUS:-0}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# All logging goes to stderr so that stdout carries exactly one thing: the new
# pane id under --no-wait, or the exported review text otherwise. That makes
# `pane=$(tuicr-wrapper-herdr --no-wait .)` work.
log_info() { echo -e "${GREEN}[tuicr]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[tuicr]${NC} $*" >&2; }
log_error() { echo -e "${RED}[tuicr]${NC} $*" >&2; }

usage() {
  cat << EOF
Usage: $(basename "$0") [--no-wait] [--focus] [directory]

Launch tuicr in a herdr split pane to review changes. The pane opens
*unfocused* so it does not steal the keyboard mid-keystroke.

Arguments:
  directory    Repository directory to review (default: current directory).
               git, jj, and mercurial checkouts are all accepted.

Options:
  --no-wait    Open the pane and exit immediately, printing the new pane id.
               Read the review with \`tuicr review comments\` when the user says
               it is ready. Prefer this when the caller is an agent that should
               not block for the length of a human review.
  --focus      Move focus to the new pane. Off by default; only pass this when
               the user just asked for the review pane and is expecting the
               jump.
  -h, --help   Show this help.

Environment variables:
  TUICR_PANE_DIRECTION   right (side-by-side) or down (default: right)
  TUICR_PANE_RATIO       split ratio passed to herdr (default: 0.5)
  TUICR_PANE_FOCUS       1 to focus the new pane (default: 0)
  TUICR_TIMEOUT_SECONDS  how long to wait for tuicr to exit (default: 3600)

Examples:
  $(basename "$0")                          # Review the current directory
  $(basename "$0") ~/project                # Review ~/project
  $(basename "$0") --no-wait ~/project      # Open the pane, do not block
  TUICR_PANE_DIRECTION=down $(basename "$0")
EOF
}

check_herdr() {
  if [[ -z "${HERDR_ENV:-}" && -z "${HERDR_PANE_ID:-}" ]]; then
    return 1
  fi
  if ! command -v herdr &> /dev/null; then
    log_error "HERDR_ENV is set but the herdr CLI is not on PATH."
    return 1
  fi
  return 0
}

check_tuicr() {
  if ! command -v tuicr &> /dev/null; then
    log_error "tuicr not found. Install it first."
    return 1
  fi
  return 0
}

# tuicr auto-detects git, jj, and mercurial, so accept all three rather than
# gating on git the way the upstream tmux wrapper does. --ignore-working-copy
# keeps the jj probe from snapshotting the working copy as a side effect.
check_repo() {
  local dir="$1"
  git -C "$dir" rev-parse --git-dir &> /dev/null && return 0
  command -v jj &> /dev/null \
    && jj --repository "$dir" --ignore-working-copy root &> /dev/null && return 0
  [[ -d "$dir/.hg" ]] && return 0
  log_error "Not a git, jj, or mercurial repository: $dir"
  return 1
}

# Exact check against the foreground process of every pane in this workspace,
# rather than matching on pane titles (a pane merely *named* tuicr is not one
# running tuicr).
find_running_tuicr_pane() {
  local workspace="${HERDR_WORKSPACE_ID:-}"
  local pane_ids pane
  if [[ -n "$workspace" ]]; then
    pane_ids=$(herdr pane list --workspace "$workspace" 2>/dev/null \
      | jq -r '.result.panes[].pane_id')
  else
    pane_ids=$(herdr pane list 2>/dev/null | jq -r '.result.panes[].pane_id')
  fi

  for pane in $pane_ids; do
    if herdr pane process-info --pane "$pane" 2>/dev/null \
      | jq -e '.result.process_info.foreground_processes[]?
               | select(.name == "tuicr")' > /dev/null 2>&1; then
      echo "$pane"
      return 0
    fi
  done
  return 1
}

launch_tuicr_pane() {
  local target_dir="$1"
  local wait_for_exit="$2"

  local split_args=(--direction "$TUICR_PANE_DIRECTION" --cwd "$target_dir")
  if [[ -n "${HERDR_PANE_ID:-}" ]]; then
    split_args=(--pane "$HERDR_PANE_ID" "${split_args[@]}")
  fi
  if [[ -n "$TUICR_PANE_RATIO" ]]; then
    split_args+=(--ratio "$TUICR_PANE_RATIO")
  fi
  if [[ "$TUICR_PANE_FOCUS" == "1" ]]; then
    split_args+=(--focus)
  fi

  local split_json new_pane_id
  split_json=$(herdr pane split "${split_args[@]}" 2>&1) || {
    log_error "herdr pane split failed: $split_json"
    return 1
  }
  new_pane_id=$(echo "$split_json" | jq -r '.result.pane.pane_id // empty')
  if [[ -z "$new_pane_id" ]]; then
    log_error "Could not read the new pane id from: $split_json"
    return 1
  fi

  log_info "Opened pane $new_pane_id ($TUICR_PANE_DIRECTION, ratio $TUICR_PANE_RATIO)"
  log_info "Directory: $target_dir"

  # `herdr pane run` injects keystrokes into whatever shell the pane started
  # (fish here), which constrains this in three ways:
  #
  #  1. Input sent before the shell finishes coming up is swallowed, and with
  #     direnv + starship that takes seconds. So probe with a cheap echo until
  #     it comes back, and only then send the real command — exactly once.
  #     Retrying the *real* command is how you end up with two tuicr processes.
  #  2. The command has to parse in fish as well as bash, so it is `;`-separated
  #     with no `&&`. Adjacent quoted strings concatenate in both.
  #  3. `herdr wait output --match` searches the whole scrollback, not just new
  #     output, and the shell echoes the line it was sent. A sentinel written
  #     plainly would therefore match its own command line the instant it was
  #     typed. Writing it as 'TUICR_EXITED''_123' means the pane displays the
  #     command with quotes in it and only the *output* is a contiguous match.
  #
  # (An earlier version wrote a temp bash script and had the pane execute it.
  # That raced: the wrapper deleted the script on the --no-wait path before the
  # pane's shell got around to running it, and fish reported "Unknown command".)
  local pid=$$
  local ready_sentinel="TUICR_READY_$pid"
  local done_sentinel="TUICR_EXITED_$pid"

  local attempt ready=0
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    herdr pane run "$new_pane_id" "echo 'TUICR_READY''_$pid'" > /dev/null 2>&1 || true
    if herdr wait output "$new_pane_id" --match "$ready_sentinel" --timeout 2000 > /dev/null 2>&1; then
      ready=1
      break
    fi
    if ! herdr pane get "$new_pane_id" > /dev/null 2>&1; then
      log_error "Pane $new_pane_id disappeared before its shell came up."
      return 1
    fi
  done
  if [[ "$ready" -ne 1 ]]; then
    log_error "Shell in pane $new_pane_id never became ready after $attempt attempts."
    return 1
  fi

  # Not waiting: run tuicr plainly. There is no point exporting to a temp file
  # nobody will read back, and the caller is told to use `tuicr review comments`.
  if [[ "$wait_for_exit" -ne 1 ]]; then
    herdr pane run "$new_pane_id" "tuicr" > /dev/null 2>&1 || {
      log_error "Could not start tuicr in pane $new_pane_id."
      return 1
    }
    log_info "tuicr is running in pane $new_pane_id (not waiting, pane not focused)."
    log_info "Read the review with: tuicr review comments --repo '$target_dir'"
    log_info "Close the pane with:  herdr pane close $new_pane_id"
    echo "$new_pane_id"
    return 0
  fi

  local output_file
  output_file=$(mktemp -t tuicr-output.XXXXXX)
  herdr pane run "$new_pane_id" \
    "tuicr --stdout > '$output_file'; echo 'TUICR_EXITED''_$pid'" > /dev/null 2>&1 || {
    log_error "Could not start tuicr in pane $new_pane_id."
    rm -f "$output_file"
    return 1
  }

  log_info "Waiting for tuicr to exit (timeout ${TUICR_TIMEOUT_SECONDS}s)..."

  # Poll in short slices instead of one long `herdr wait output` so we notice a
  # pane the user closed by hand, which would otherwise hang until the timeout.
  local elapsed=0 slice=5 finished=0
  while (( elapsed < TUICR_TIMEOUT_SECONDS )); do
    if herdr wait output "$new_pane_id" --match "$done_sentinel" \
      --timeout $((slice * 1000)) > /dev/null 2>&1; then
      finished=1
      break
    fi
    if ! herdr pane get "$new_pane_id" > /dev/null 2>&1; then
      log_warn "Pane $new_pane_id went away before tuicr reported an exit."
      break
    fi
    elapsed=$((elapsed + slice))
  done

  if [[ "$finished" -eq 1 ]]; then
    log_info "tuicr finished"
    herdr pane close "$new_pane_id" > /dev/null 2>&1 || true
  elif (( elapsed >= TUICR_TIMEOUT_SECONDS )); then
    log_warn "Timed out after ${TUICR_TIMEOUT_SECONDS}s; leaving pane $new_pane_id open."
  fi

  if [[ -s "$output_file" ]]; then
    echo ""
    echo "=== TUICR INSTRUCTIONS ==="
    cat "$output_file"
    echo "=== END TUICR INSTRUCTIONS ==="
  else
    log_info "No instructions exported to stdout."
    log_info "Read saved comments with: tuicr review comments --repo '$target_dir'"
  fi

  rm -f "$output_file"
}

main() {
  local wait_for_exit=1
  local target_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --no-wait) wait_for_exit=0; shift ;;
      --focus) TUICR_PANE_FOCUS=1; shift ;;
      --) shift; break ;;
      -*) log_error "Unknown option: $1"; usage; exit 1 ;;
      *) target_dir="$1"; shift ;;
    esac
  done

  check_tuicr || exit 1

  target_dir="${target_dir:-.}"
  target_dir=$(cd "$target_dir" && pwd)
  check_repo "$target_dir" || exit 1

  if ! check_herdr; then
    log_error "Not running inside herdr!"
    echo ""
    echo "This wrapper drives herdr panes. If you are in tmux use tuicr-wrapper.sh,"
    echo "in zellij use tuicr-wrapper-zellij.sh, and otherwise just run \`tuicr\`"
    echo "in the repo yourself and attach with \`tuicr review list\`."
    exit 1
  fi

  local existing
  if existing=$(find_running_tuicr_pane); then
    log_warn "tuicr is already running in pane $existing"
    log_info "Focus it with: herdr pane focus --direction $TUICR_PANE_DIRECTION"
    echo "$existing"
    exit 0
  fi

  launch_tuicr_pane "$target_dir" "$wait_for_exit"
}

main "$@"
