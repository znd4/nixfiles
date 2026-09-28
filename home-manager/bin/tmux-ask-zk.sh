#!/usr/bin/env bash
# Open a tmux popup that shows the ask-zk queue of one Claude Code session.
#
# Usage: tmux-ask-zk <client-name> <pane-id>
#
# The key binding runs this script through `run-shell`. run-shell has no
# current client, so display-popup needs an explicit client (-c).
#
# Claude Code writes one <pid>.json file per live session into
# ~/.claude/sessions/. The `tmux` field ends in ".<pane-id>", for example
# "work:@103.%125". After a crash, a file can stay after its process stops,
# so the script ignores a match when its pid is not alive. When more than
# one live session matches, the file with the newest updatedAt wins.
#
# The popup attaches a nested tmux session named _ask-zk-<tag>. When you
# press the key inside the popup, the key binding sees that session name and
# kills the nested session. This closes the popup.

client=$1
pane=$2
sessions_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
socket="${TMUX%%,*}"

sid=$(
  jq -r --arg suffix ".$pane" \
    'select((.tmux // "") | endswith($suffix))
     | "\(.pid) \(.updatedAt // 0) \(.sessionId)"' \
    "$sessions_dir"/*.json 2>/dev/null |
    while read -r pid updated id; do
      if kill -0 "$pid" 2>/dev/null; then
        echo "$updated $id"
      fi
    done |
    sort -rn |
    head -n1 |
    cut -d' ' -f2
)

if [ -z "$sid" ]; then
  tmux display-message -c "$client" "ask-zk: no live Claude Code session in pane $pane"
  exit 0
fi

tag="claude-${sid:0:8}"
name="_ask-zk-$tag"

tmux display-popup -c "$client" -E -w 85% -h 80% -T " asks: $tag " \
  "env -u TMUX tmux -S '$socket' new-session -A -s '$name' 'ask-zk tui --tag $tag' \\; set-option status off"
