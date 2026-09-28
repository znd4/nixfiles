---
name: herdr-development
description: Change the herdr configuration that nixfiles manages — keybindings, the generated config.toml, or the herdr-* scripts (the alt+d launcher, the alt+r review workspace). Use when you edit home-manager/programs/herdr.nix or home-manager/bin/herdr-*, or when a herdr change "does not take effect" after a home-manager switch. Do not use it to drive panes at run time; `herdr --skill` covers that.
---

# herdr-development

`~/nixfiles/docs/herdr.md` explains each step below. Read it before a change
that is more than one line.

## Where things are

- `home-manager/programs/herdr.nix` — package pin, keybindings, generated
  `config.toml`, the wrapped scripts.
- `home-manager/bin/herdr-launcher` — the `alt+d` picker.
- `home-manager/bin/herdr-mr-review.py` — the `alt+r` review workspace.

The launcher shows its picker in television (`tv`), a terminal fuzzy finder.

## The tmux equivalents

Under tmux, different files set the same keys. Edit those files, not
`herdr.nix`:

| Key | herdr script | tmux replacement |
|---|---|---|
| `alt+d` | `herdr-launcher` | `sesh connect` popup, in `programs/tmux.nix` |
| `alt+m` | `herdr-clone` | `_sesh-cl-fuzzy` popup, in `programs/tmux.nix` |
| `alt+s` | `herdr-new-named` | `programs.tmux-new-session`, in `programs/tmux.nix` |
| `alt+r` | `herdr-mr-review` | `programs/tmux-mr-review.nix` (opens Hunk, not tuicr) |
| `alt+shift+g` | `herdr-agent-lazygit` | `M-G` popup at `#{pane_current_path}`, in `programs/tmux.nix` |
| `prefix+alt+g` | lazygit pane | `prefix M-g` split, in `programs/tmux.nix` |
| `prefix+space` | herdr-thumbs plugin | `tmux-thumbs` plugin, in `programs/tmux.nix` |

To open a new worktree with an agent in it, use `workmux add` (configured in
`programs/workmux.nix`).

## The change chain

1. **Edit** in a worktree of `~/nixfiles`.
2. **Test a script without a rebuild.** Call the launcher subcommands
   directly. They are its whole interface:

   ```bash
   HERDR_LAUNCHER_COLOR=0 ./home-manager/bin/herdr-launcher list
   HERDR_LAUNCHER_COLOR=0 ./home-manager/bin/herdr-launcher preview '<entry>'
   ./home-manager/bin/herdr-launcher resolve '<entry>'   # says what enter would do
   ```

   Also run `bash -n` and `shellcheck -s bash` on a changed script, and
   `nix-instantiate --parse` on a changed `.nix` file.
3. **Push** to `main`. If another flake uses this repo as an input, update
   that input in the other flake too.
4. **Switch** with `nh home switch`.
5. **Check the reload.** The switch reloads the running server (the
   `herdrReloadConfig` activation step). If the switch prints
   `herdr: reload-config did not apply cleanly`, fix what it lists and switch
   again. To reload by hand:

   ```bash
   herdr server reload-config   # expect "status":"applied" and no diagnostics
   ```

   A stale server runs the previous build of each script and shows no error.
   See [`docs/herdr.md`](https://github.com/znd4/nixfiles/blob/main/docs/herdr.md).
6. **Check** with `herdr config check`, then use the keybinding once.

## Traps

- `herdr-launcher` runs inside a `writeShellApplication` wrapper, so `$0` is
  the wrapper, not the repo file. The script calls itself again through
  `$SELF`. Do not remove the `case $0` block that sets `$SELF`.
- television accepts only one `--source-command`. To add a new kind of entry,
  give it a new leading symbol (sigil) in the one list. Do not add a second
  source.
- `herdr <noun> list` always writes JSON. `workspace list` has no `cwd`. To
  find a workspace directory, join it against `pane list`.
- A tab label is a number until someone renames it. Test for all digits, not
  `.label == .number` — closing a tab renumbers the rest but keeps their
  labels.
