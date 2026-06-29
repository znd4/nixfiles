---
name: hunk-mr
description: Review a GitLab MR or GitHub PR in the Hunk terminal diff viewer and publish review notes back to the forge as inline comments. Use when the user is reviewing a merge request / pull request locally with Hunk and wants comments to round-trip to GitLab/GitHub, or asks to "push my hunk notes to the MR".
---

# hunk-mr

`hunk-mr` bridges the Hunk diff viewer to GitLab MRs / GitHub PRs. It self-derives
all forge context (host, project, MR/PR number, diff SHAs) from the current
checkout's `origin` remote and the remote branch pointing at `HEAD`, so it must be
run **from inside a checkout/worktree of the MR/PR's source branch**.

This skill complements the bundled `hunk-review` skill: use `hunk-review`
(`hunk session …`) to *drive the live TUI and add notes*; use `hunk-mr` to *open
the right diff* and *publish notes to the forge*.

## Commands

```bash
hunk-mr open                # open the MR/PR diff in Hunk (origin/target...HEAD)
hunk-mr info                # print derived forge context (debug)
hunk-mr pull                # import the MR/PR's UNRESOLVED review threads as notes
hunk-mr pull --all          # include resolved threads too
hunk-mr push                # DRY RUN: preview which notes would be published
hunk-mr push --post         # actually create the comments (asks for confirmation)
hunk-mr push --post --yes   # publish without the gum confirmation prompt
hunk-mr push --type all     # include agent/ai notes, not just human (user) notes
hunk-mr push --number 123   # override MR/PR number if auto-detection fails
```

## Workflow

1. `hunk-mr open` — launches the Hunk TUI showing the MR/PR diff for the user.
2. Use the `hunk-review` skill (`hunk session navigate` / `hunk session comment
   add|apply`) to steer the user's view and leave inline notes on specific lines.
   Notes the user wants published are normal `comment add` notes; they default to
   the `user` type, agent-authored ones are `agent`/`ai`.
3. `hunk-mr push` (dry run) to show the user exactly what will be posted.
4. After the user approves, `hunk-mr push --post`.

## Pulling forge threads in (`hunk-mr pull`)

`hunk-mr pull` imports the MR/PR's existing inline review threads into the open
Hunk session as notes, so the user can see other people's feedback next to the
code. One Hunk note is created per individual comment (replies included), labelled
with the real reviewer's name via `--author`, with a `↩ <forge-url>` footer so the
user can jump back to reply.

- Defaults to **unresolved threads only** (the open feedback); `--all` includes
  resolved ones.
- Requires `hunk-mr open` first (it adds notes to the live session for *this*
  checkout).
- Comments on lines not present in the loaded diff (e.g. outdated) are skipped and
  reported.
- **Imported notes are never re-published.** They land in Hunk's agent/live bucket
  and carry the `↩` footer, so `hunk-mr push` (which harvests `user` notes) will not
  echo them back to the forge — even with `--type all`. Do not try to "push" pulled
  comments.

This is a one-way, lossy snapshot for context: Hunk's flat note model has no
threading or resolved/unresolved state, so to actually reply or resolve, the user
goes back to the forge (via the `↩` link).

## Notes → comments mapping

- Each Hunk note is published as one inline diff comment / discussion at its file
  and line. `newLine` → the new (RIGHT) side; `oldLine` → the old (LEFT) side.
- The comment body is the note `summary`, followed by `rationale` if present, plus
  a `— via hunk-mr` footer.
- `--type` selects which notes to publish: `user` (default, human notes), `agent`,
  `ai`, or `all`.

## Important constraints

- Hunk notes live only in the **running TUI session** — they vanish when the
  window closes. Run `hunk-mr push` while the Hunk window for this checkout is
  still open.
- `push` defaults to a **dry run**. Never pass `--post` (or `--yes`) unless the
  user has explicitly approved publishing to the forge.
- If `push` reports "could not read Hunk notes", a Hunk session is not open in
  this checkout — ask the user to run `hunk-mr open` first.
- If auto-detection of the MR/PR number fails (detached worktree with an unusual
  branch layout), pass `--number <n>`.
