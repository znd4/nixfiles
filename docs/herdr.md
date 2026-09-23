# herdr

[herdr](https://herdr.dev) is the terminal multiplexer, running directly in
Ghostty with no tmux layer under it. `herdr --skill` covers the runtime CLI;
this file covers configuration.

## Where it is wired

| What | Where |
| --- | --- |
| Package pin, keybindings, generated `config.toml` | `home-manager/programs/herdr.nix` |
| `alt+d` workspace / tab / directory picker | `home-manager/bin/herdr-launcher` |
| `alt+r` MR review workspace | `home-manager/bin/herdr-mr-review.py` |
| `alt+m` clone-creator, `alt+s` new workspace | `herdr.nix`, inline |
| Live server upgrade | `herdr.nix`, `herdrHandoff` |
| Config reload after a switch | `herdr.nix`, `herdrReloadConfig` |

## Changing the config: the switch reloads the server

`nix run .#home-manager-switch` rewrites `~/.config/herdr/config.toml`, but the
running server keeps the copy it read at start-up. So at the end of each
switch, the `herdrReloadConfig` activation step in `herdr.nix` runs:

```bash
herdr server reload-config
```

A `herdr: reload-config did not apply cleanly` warning means the new config
has problems. Fix what it lists, then switch again. You can also run the
command by hand. `herdr config --help` does not list it; it is under
`herdr server`.

A missed reload shows no error. Each keybinding holds a nix store path, so a
stale server runs the previous build of each script.

## The alt+d launcher

`herdr-launcher` is inlined into a `writeShellApplication`, so `$0` at run time
is the wrapper, not the file in this repo. It calls back into itself for `list`,
`preview` and `resolve` to keep `runtimeInputs` on `PATH` in sub-invocations.

Test without a rebuild:

```bash
HERDR_LAUNCHER_COLOR=0 ./home-manager/bin/herdr-launcher list
HERDR_LAUNCHER_COLOR=0 ./home-manager/bin/herdr-launcher preview '<entry>'
./home-manager/bin/herdr-launcher resolve '<entry>'   # says what enter would do
```

television drives it inline with no cable channel — `--source-command` cannot
be given twice and tv has no "switch source" action. That single-source
constraint is why each line carries a leading sigil (`▣` workspace, `󰓩` tab,
`󰉋` directory): the preview and the final pick both read `{}` with no column
hidden.

## Reading herdr's own data

`herdr <noun> list` always writes JSON to stdout; there is no format flag.

- `workspace list` → `.result.workspaces[]`. Carries no `cwd` — join against
  `pane list` to find a workspace's directory.
- `tab list` → `.result.tabs[]`
- `pane list` → `.result.panes[]`. Carries `cwd`, `foreground_cwd`,
  `terminal_title_stripped` and `focused`.

`herdr pane read <pane> --format text` is the one call that does take a format.

**A tab label is a number until someone renames it.** Do not filter defaults
with `.label == .number` — closing a tab renumbers the remaining tabs but
leaves their labels alone. Test for all digits instead.
