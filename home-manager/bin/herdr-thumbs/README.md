# herdr-thumbs

[tmux-thumbs](https://github.com/fcsonline/tmux-thumbs) for
[herdr](https://herdr.dev). Press a key, and every URL / path / hash / IP on the
focused pane gets a short **hint label**. Type the hint to act on that match:

- **lowercase hint → copy to clipboard** (default action)
- **UPPERCASE hint → open** in the browser / default app (`open` / `xdg-open`)

`esc` (or `q`, when no hint starts with `q`) cancels.

This mirrors the old tmux config:

```tmux
set -g @thumbs-upcase-command 'open {}'
set -g @thumbs-regexp-1 '(?:https?://|git@|git://|ssh://|ftp://|file:///)[^ ]+[^.,;:)\]> ]'
# default action: copy to clipboard
```

## How it works

herdr has no built-in copy-mode hint picker, but it has all the pieces:

1. A `[[panes]]` entrypoint with `placement = "overlay"` opens a temporary
   zoomed pane over the active one and restores focus/zoom on exit.
2. herdr passes the *client-focused* pane in `HERDR_PLUGIN_CONTEXT_JSON`
   (`focused_pane_id`) — **not** `HERDR_PANE_ID`, which is the overlay's own
   pane.
3. `thumbs.py` reads that pane's visible text via `herdr pane read`, regex-matches
   hintable strings, draws them with curses hint labels, reads one hint, and runs
   the configured action.

Everything is a single dependency-free `uv` script (stdlib `curses`), so there's
no build step. The matcher/action layer is import-safe and unit-tested without a
real herdr or tty (`test_thumbs.py`).

### Why Python and not Rust?

Measured on the prototype (macOS, herdr 0.7.1):

| phase | time |
| --- | --- |
| warm launch (uv env cached) | ~40–50 ms |
| match 160 hits across 40 lines | ~10 ms |
| cold uv (first run only) | ~480 ms |

Warm launch is well under the ~100 ms perceptual threshold, and the dominant
interactive cost is the `herdr pane read` round-trip + terminal redraw, which a
Rust rewrite wouldn't change. Python stays.

## Install (local dev)

```sh
herdr plugin link /path/to/herdr-thumbs
```

Then bind a key in your herdr `config.toml` (the plugin manifest can't declare
keybindings — herdr only reads `panes`/`actions`/`events`/`link_handlers` from
it):

```toml
# prefix+space, matching the tmux-thumbs default. Change to taste, e.g.
# "alt+f" for a no-prefix chord.
[[keys.command]]
key = "prefix+space"
type = "plugin_pane"
command = "znd4.thumbs.pick"
description = "thumbs: hint + copy/open matches"
```

Reload: `herdr server reload-config`.

> Note: `type = "plugin_pane"` opens the manifest pane entrypoint `pick`. If your
> herdr version names it differently, check `herdr plugin list --plugin
> znd4.thumbs --json` and the config reference.

## Configuration

Optional TOML at `$(herdr plugin config-dir znd4.thumbs)/config.toml`. All keys
are optional and fall back to the built-in defaults:

```toml
# Hint alphabet (home-row first). Two-char hints are auto-generated as needed.
alphabet = "asdfghjklqwertyuiopzxcvbnm"

# Ordered regexes; earlier patterns win on overlap. Defaults cover URLs/git
# remotes, paths, uuids, git shas, IPs, and host:port.
patterns = [
  "(?:https?://|git@|git://|ssh://|ftp://|file:///)[^ \\t\\r\\n]+[^.,;:)\\]>\\s]",
  # ...
]

# Default action = lowercase hint. pbcopy has no argv, so pass on stdin.
default_action = ["pbcopy"]
default_action_stdin = true

# Upcase action = uppercase hint. "{}" is replaced with the match.
upcase_action = ["open", "{}"]
upcase_action_stdin = false
```

**Linux clipboard**: override `default_action` to `["wl-copy"]` (Wayland) or
`["cb", "copy"]`, and `upcase_action` to `["xdg-open", "{}"]`.

## Development

```sh
uv run test_thumbs.py          # pure matcher/hint/action unit tests

# Drive the whole pipeline headlessly (no tty), acting on a chosen hint:
printf 'see https://example.com/x\n' | THUMBS_STDIN=1 THUMBS_AUTO=s ./thumbs.py
#   THUMBS_AUTO=s  -> copy the match with hint 's'
#   THUMBS_AUTO=S  -> open  it (uppercase = upcase action)

# Dump the invocation context herdr passes into an overlay:
herdr plugin pane open --plugin znd4.thumbs --entrypoint pick \
  --placement overlay --env THUMBS_DEBUG=/tmp/thumbs_debug.json
```
