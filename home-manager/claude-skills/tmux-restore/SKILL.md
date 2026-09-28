---
name: tmux-restore
description: Restore the Claude Code sessions that a tmux crash or reboot killed, each by its exact session UUID, from the tmux-snapshot files.
disable-model-invocation: true
---

# Restore Claude Code sessions after a tmux crash

A launchd job runs `tmux-snapshot` every 30 minutes and at login. For each tmux
pane that runs Claude Code, it records the tmux session, the window, the cwd,
and the session UUID. The files are in `~/.local/state/tmux-snapshots/`:

- `latest.json` is the newest state.
- `snapshot-<unix-epoch>.json` is the history for about 7 days. The job writes
  a new history file only when the state changes.

If a capture finds zero Claude Code panes but `latest.json` has some, the job
keeps the old `latest.json`. Thus, after a tmux crash, `latest.json` usually
still shows the sessions from before the crash.

`tmux-restore` reads a snapshot file. For each session, it opens a window and
runs `claude --resume <uuid>` in the saved cwd.

Do not use `workmux resurrect` for Claude Code sessions. It runs
`claude --continue`, which opens the newest session in the directory. It also
restores only one agent per worktree.

## Procedure

1. Do a dry run. This is the default. It prints the tmux commands and changes
   nothing:

   ```bash
   tmux-restore
   ```

2. Find the correct snapshot. Read `capturedAt` in the dry-run output. If a
   snapshot was captured after the crash, it can show the state after the
   crash. In that case, pick the newest history file from before the crash:

   ```bash
   ls -lt ~/.local/state/tmux-snapshots/ | head
   tmux-restore --file ~/.local/state/tmux-snapshots/snapshot-<epoch>.json
   ```

3. Show the plan to the user. Then run it:

   ```bash
   tmux-restore --apply [--file PATH] [--only UUID[,UUID...]]
   ```

4. Make sure each restored session runs. Wait a few seconds, then run
   `tmux-snapshot`. Compare the UUIDs in `latest.json` with the plan. If a
   session does not run after the restore, report it as a failure.

## Rules

- **Do not resume a session that is already running.** When two processes use
  one transcript, the session gets damaged. `tmux-restore` skips each UUID that
  a live `~/.claude/sessions/<pid>.json` holds. Do not bypass this check.
- **Create only. Do not destroy.** The script adds sessions, windows, and
  panes. Never close, rename, or move a pane that already exists.
- **Report entries that have no UUID** (`source: "unknown"`). The script
  cannot resume them. To find those sessions, look at the modification times
  of the transcripts in `~/.claude/projects/`. The `herdr-restore` skill
  explains this method.
