#!/usr/bin/env bash
# herdr-thumbs launcher action.
#
# Keybindings can only bind `shell` / `pane` / `plugin_action` command types
# (no `plugin_pane`), so opening the overlay from a key goes through this action.
# It just asks herdr to open the plugin's `pick` overlay pane. The overlay reads
# the *client-focused* pane out of HERDR_PLUGIN_CONTEXT_JSON (see thumbs.py), so
# no target needs to be threaded through here.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

exec "$herdr" plugin pane open \
  --plugin "${HERDR_PLUGIN_ID:-znd4.thumbs}" \
  --entrypoint pick \
  --placement overlay
