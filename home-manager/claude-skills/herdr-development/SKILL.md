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
4. **Switch** with `nix run .#home-manager-switch`.
5. **Reload.** The switch alone does not change the running server:

   ```bash
   herdr server reload-config   # expect "status":"applied" and no diagnostics
   ```

   The running server keeps the `config.toml` it read at start-up. Each
   keybinding holds a nix store path. Without a reload, the server runs the
   previous build of each script and shows no error. `herdr config --help`
   does not list the reload. It is under `herdr server`.
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
