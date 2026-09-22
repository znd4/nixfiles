---
name: ask-zk
description: Queue a task that only the user can do — an interactive login, a TouchID prompt, a button to click, a review to approve. Use when you are about to write "you'll need to…", "run this yourself", or hand the user a command in a code block. Also covers reading the queue and closing items.
---

# The ask queue

An **ask** is something the user must personally type, click, or approve.
Agents cannot do these: interactive browser logins, hardware-key prompts, a
merge request waiting on their review.

The CLI is `ask-zk`. It writes one markdown note per item into a
[zk](https://github.com/zk-org/zk) notebook. The user reads and edits items in
any markdown editor. The user's status line shows
`▲ N asks waiting on you`.

## Adding one

```bash
ask-zk add --what "Re-authenticate the deploy identity (browser)" \
           --why  "every deploy call returns 403 until it is done" \
           --cwd  /path/if/the/command/needs/one \
           --cmd  'gcloud auth login --update-adc' \
           --verify 'gcloud auth print-access-token >/dev/null 2>&1'
```

- **`--what` is imperative and specific.** `--why` says what stays broken.
- **Always give a `--verify` probe.** Exit 0 means done. The queue auto-closes
  the item when the user acts outside the queue. An item with no probe can never
  close itself.
- Repeat `--cmd` for a sequence. Paste the real command, not a description.
- **Never put a secret in `--cmd`.** Pipe the credential in at run time.
- One item for one thing the user must do.

**The note must be executable on its own.** The user acts with only the note
open. Put every URL inline. An ask that says "see note X" or "add Y before you
send" is not finished.

When the action is not a shell command (paste text, approve a request, click a
button), `--cmd` still carries the payload. For a short payload, pipe it to the
clipboard. For a long one, write a file and let `--cmd` copy it.

No command can observe a manual action automatically. Write the trace yourself:
add a second `--cmd` that records the action in a file, and a `--verify` that
reads that file back.

## Reading it

```bash
ask-zk --plain --no-verify        # agents: always this form
ask-zk sweep                      # run the probes; closes what passed
ask-zk count                      # for scripts
```

**Never run bare `ask-zk` as an agent.** It runs every `--verify` probe, up to
8 s each, and can exceed the tool timeout. Run `ask-zk sweep` separately when
you want the probes.

**Exit 3 is not a failure.** `count` exits 3 when items are stale
(`ASK_STALE_DAYS`, default 7); the count on stdout is still correct. Bare
`ask-zk` always exits 0. Only exit 2 means the call was wrong.

| code | meaning |
|---|---|
| 0 | success |
| 1 | item not found |
| 2 | usage error, or not a zk notebook |
| 3 | `count` worked, but some items are stale |
| 130 | interrupted |

To list a tagged set: `ask-zk --no-verify list --tag <tag>`. **`--no-verify` is
a global flag -- put it before `list`.** After `list` it fails with
`unrecognized arguments`.

## Closing it

**`ask-zk done <id>` belongs to the user, not to you.** Agents use
`ask-zk drop <id>`, and only when the item is no longer needed — for example
when you answered the question yourself, so there is no longer a button for the
user to press.

Closing changes `- [ ] ` to `- [x] ` and adds `closed:` and `closed_ts:` to the
frontmatter. **It never deletes the note.**

## How state works

**State lives in one place: the checkbox.** `zk` cannot filter on frontmatter,
so a frontmatter key cannot hold state. A separate `#open` tag would duplicate
the checkbox and could disagree with it.

```python
OPEN_BOX = re.compile(r"^- \[ \] ")
DONE_BOX = re.compile(r"^- \[x\] ", re.I)
```

Both anchor at `^`, so **an indented checkbox does not count**. The space after
`]` is mandatory. `- [-]` and every other bracket content match neither pattern;
the note leaves the queue silently.

**`#ask` is the gate, not the state.** A checkbox line without `#ask` is not a
queue item. The tag marks the note as a queue item; it does not show whether the
item is open.

The script reads tags with `(?<!\S)#([a-z0-9_-]+)` -- lowercase only, whitespace
required before the `#`. A `#` inside prose or a URL (e.g. `(#example`) does not
register as a tag.

`#ask` always comes first, after two spaces:

```
- [ ] Mint the deploy credential  #ask #infra
```

## Frontmatter

Six keys, all written by the script. Do not add others -- `zk` cannot filter on
frontmatter.

| key | when |
|---|---|
| `created` | always |
| `cwd` | with `--cwd` |
| `by` | with `--by`, or from `ASK_BY` / `USER` |
| `closed` | on close — `done` or `drop` |
| `closed_ts` | on close |
| `ask_id` | **legacy. Read, never written.** |

`ask_id` holds ids from an earlier SQLite store. Old merge requests and tickets
reference them, so they still resolve. New notes do not get one.

**`<id>` is the note filename stem** (`7e7g`).

## Notebook path

Nix sets `ASK_NOTEBOOK` from `programs.ask-zk.notebook` and passes the same
value to the status line. Set `ASK_NOTEBOOK` to override for one invocation.

The script **ignores `ZK_NOTEBOOK_DIR`** deliberately. `zk` lets cwd
auto-discovery override that variable, so an agent inside a different notebook
would write items to the wrong place. The path is always explicit.
