# Reviewing MRs / PRs with Hunk (`hunk-mr`)

[Hunk](https://github.com/modem-dev/hunk) is a terminal diff *viewer* — it renders
diffs and lets you attach inline review notes, but it has **no concept of a merge
request or pull request** and never talks to GitLab/GitHub. `hunk-mr` is the thin
bridge that closes that gap:

```
fetch the MR/PR diff   →   review it in Hunk   →   publish notes back to the forge
      (hunk-mr open)         (hunk + notes)           (hunk-mr push --post)

            ↑  optionally pull existing reviewer threads in for context
                              (hunk-mr pull)
```

Both ends — fetching the diff and posting comments — are done by `hunk-mr` using
`gh` (GitHub) or `glab` (GitLab, including your self-hosted hosts). Hunk in the
middle is purely the review surface.

## How it figures out the MR/PR

`hunk-mr` is **stateless**. Run it from inside a checkout or worktree of the MR/PR's
source branch and it derives everything itself:

| Needs | Derived from |
| --- | --- |
| host + project | `git remote get-url origin` |
| forge (github/gitlab) | `github.com` ⇒ GitHub, else GitLab |
| source branch | remote branch pointing at `HEAD` (works on detached review worktrees) |
| MR/PR number | `gh pr list --head <branch>` / `glab` API by source branch |
| base/head/start SHAs | the forge's diff refs (needed for GitLab line positions) |

Nothing is persisted, so it works in any MR/PR checkout — including the review
worktrees produced by the (dormant) `tmux-mr-review` popup.

## Usage

```bash
# In a worktree of the MR/PR branch:
hunk-mr open            # opens the MR/PR diff in Hunk (origin/target...HEAD)
hunk-mr info            # show what it detected (forge/project/number/SHAs)

# Optionally pull existing reviewer threads in for context:
hunk-mr pull            # imports UNRESOLVED threads as notes (--all for resolved)

# Leave your own inline notes in the Hunk TUI (the `c` note affordance), then:
hunk-mr push            # DRY RUN — prints exactly what would be posted
hunk-mr push --post     # publishes (asks for confirmation via gum)
```

### `push` options

| Flag | Meaning |
| --- | --- |
| `--type <user\|agent\|ai\|all>` | Which Hunk notes to publish (default `user` = your own notes) |
| `--post` | Actually publish; **without it, `push` is a dry run** |
| `--yes`, `-y` | Skip the confirmation prompt |
| `--number <n>` | Override the MR/PR number if auto-detection fails |

Each note becomes one inline comment at its file+line. `newLine` notes attach to
the new (RIGHT) side, `oldLine` notes to the old (LEFT) side. The comment body is
the note's summary, then its rationale (if any), then a `— via hunk-mr` footer.

## Pulling reviewer threads in (`hunk-mr pull`)

`hunk-mr pull` imports the MR/PR's existing inline review threads into your open
Hunk window, so other people's feedback shows up next to the code as you review.

```bash
hunk-mr open      # first, so there's a session to import into
hunk-mr pull      # unresolved threads only
hunk-mr pull --all   # include resolved threads too
```

- **One note per comment** (replies included), labelled with the reviewer's real
  name and a `↩ <forge-url>` footer to jump back and reply.
- **Unresolved only by default** — the feedback you still need to act on.
- Comments on lines that aren't in the loaded diff (e.g. outdated) are skipped and
  reported.

### Why imported comments aren't "agent" in spirit (but are mechanically)

Hunk's `comment add` has **no `--type` flag** — the type is decided by *how* a note
is created. Only notes you type in the TUI are `user`; anything inserted via the
CLI lands in the **agent/live** bucket. So `pull` can't make these `user` notes
even though they're written by humans. Two things make that fine:

1. `--author` carries the real reviewer name, so they *read* as "alice said …",
   not "an AI said …".
2. The bucket split is a safety feature: `hunk-mr push` harvests `user` notes, so
   imported threads (agent/live, plus a `↩` footer marker) are **never echoed back
   to the forge** — not even with `push --type all`. Your notes go out; theirs
   don't.

It's a **one-way, lossy snapshot for context**, not a sync — Hunk's flat note model
has no threading or resolved state, so to reply or resolve you go back to the forge
via the `↩` link.

## Things to know

- **Notes are ephemeral.** They live only in the running Hunk TUI session and are
  gone when you close the window. Run `hunk-mr push` *before* closing Hunk.
- **`push` is dry-run by default** — a deliberate guardrail, since publishing to a
  forge is outward-facing. You always see a preview first.
- **Comment-list schema.** `hunk-mr push` reads `hunk session comment list --json`.
  The exact field names there can shift between Hunk versions; the `jq` normalizer
  in [`home-manager/bin/hunk-mr.sh`](../home-manager/bin/hunk-mr.sh) accepts the
  common aliases (`filePath`/`file`, `newLine`/`new_line`, …). If a new Hunk
  release renames fields and notes stop coming through, that normalizer is the one
  place to adjust.
- **Agent-driven reviews.** An AI agent can drive the same flow via the installed
  `~/.claude/skills/hunk-mr/` skill (and Hunk's own `hunk-review` skill): it steers
  your live Hunk window with `hunk session …` and leaves notes, then you (or it,
  with approval) run `hunk-mr push --post`.

## Where it's wired

- Tool + skill: [`home-manager/programs/hunk-mr.nix`](../home-manager/programs/hunk-mr.nix)
- Script: [`home-manager/bin/hunk-mr.sh`](../home-manager/bin/hunk-mr.sh)
- Agent skill: [`home-manager/claude-skills/hunk-mr/SKILL.md`](../home-manager/claude-skills/hunk-mr/SKILL.md)
- Hunk itself / git pager integration: [`home-manager/programs/hunkdiff.nix`](../home-manager/programs/hunkdiff.nix)
