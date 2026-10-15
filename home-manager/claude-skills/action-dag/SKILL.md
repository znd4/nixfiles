---
name: action-dag
description: Draw and update the action graph (DAG) of a multi-step goal, with live status from GitLab MRs, ask-zk items and read-only probes. Use when the user asks for a DAG, an action graph, a cutover map, "what's blocking", "what do I need to do next" or "what is left" for a goal with many steps, or types /action-dag. Also use when a fact about such a goal changes (an MR merges, a decision is made, a step is added) and its graph must show it.
user_invocable: true
---

# action-dag

An **action graph** shows the steps to a goal, the order of the steps, and the
status of each step. One goal has one graph file. The `action-dag` CLI reads
the file, gets the live status of each step, and writes one HTML page.

## Terms

- **DAG**: directed acyclic graph. The arrows have a direction, and no path
  of arrows goes back to its start.
- **Node**: one step. It shows as a card on the page.
- **Edge**: `[A, B]` means "A must finish before B". A is a **predecessor**
  of B.
- **Board**: the main part of the page. It shows the cards in columns.
- **Column**: a vertical group of cards on the board. On each run, the CLI
  calculates the columns from the state of each node (see
  [The page](#the-page)).
- **Open step**: a node that is not in the `done` state.
- **Lane**: an optional label in the YAML file. `lanes:` lists the labels, and
  `lane:` gives one to a node. The [detail panel](#the-page) shows it. It does
  not set the column of a card.
- **State**: one of six values for each node:

  | State | Meaning |
  |---|---|
  | `next` | the step is ready, and the owner can do it now |
  | `wait` | the step waits for a review or for a different person |
  | `decide` | the step needs a decision from the owner |
  | `blocked` | a predecessor is not done |
  | `done` | the step is finished |
  | `unknown` | the CLI could not get the status |

- **Status source**: the place where the CLI reads the status of a node: an
  MR, an ask, a probe, or a value that you write by hand (`manual:`).
- **Ask**: an item in the [ask-zk](../ask-zk/SKILL.md) queue: a task that only
  the user can do. One ask is one note in the
  [zk](https://github.com/zk-org/zk) notebook. The user closes an ask when
  they tick its checkbox.
- **Probe**: a read-only shell command in a `probe:` source. Exit code 0
  means that the step is done.
- **MR**: a GitLab
  [merge request](https://docs.gitlab.com/ee/user/project/merge_requests/).
  The **iid** is its number in its project (`!2041` has the iid 2041). The CLI
  reads MRs with [glab](https://gitlab.com/gitlab-org/cli).
- **Hub note**: the zk note for one workstream. It links to the other notes of
  the workstream. These other notes are **spoke notes**.
- **Cutover**: the step that moves a service from the old system to the new
  system.
- **Side track**: a node that is not on the path to the goal. It has no lane
  and no edges. It is not in a column.
- **Done row**: a row of links to finished work, under the board.
- **Artifact**: a web page on claude.ai that the Artifact tool publishes.

## Files

The files are in the zk notebook, next to the hub note of the goal. The
notebook is `$ACTION_DAG_NOTEBOOK`. The default is the ask-zk notebook.

| File | Written by | Contents |
|---|---|---|
| `<goal>.dag.yaml` | you, with the [editing commands](#edit-the-graph) | the graph: nodes, edges, status sources |
| `<goal>.dag.html`, or the `output:` path | `action-dag` | the page. Each run writes it again. Do not edit it. |
| `<goal>.dag.state.json` | `action-dag` | the state of each node at the last run. It is always next to the YAML file. |
| `<goal>.public.dag.html`, or the `--output` path | `action-dag --public` | the page to share (see [Share the page](#share-the-page)). |

The CLI writes the page to a temporary file in the same directory, then
renames it. Thus a browser that reloads the page never reads a half-written
file.

## Commands

```bash
action-dag <goal>              # get the status, write the page, print a summary
action-dag <goal> --no-open    # the same, but never open the page (use this in agents)
action-dag <goal> --watch      # write the page again every 5 minutes, until Ctrl-C
action-dag <goal> --watch 2    # the same, every 2 minutes
action-dag <goal> --check      # check the YAML only. Get no status
action-dag <goal> --json       # print the state of each node as JSON, not the summary
action-dag --list              # list the graphs in the notebook
action-dag path/to/x.dag.yaml  # use a graph file in a different directory
action-dag <goal> --public     # write the page to share: <goal>.public.dag.html
action-dag <goal> --public --output <file> --redact-pattern '<regex>'
                               # the same, to <file>, and remove each match of <regex>
```

`<goal>` is the file name without `.dag.yaml`.

The names `set`, `add`, `edge`, `done` and `rm` are reserved as the first
argument (see [Edit the graph](#edit-the-graph)). To render a goal that has
one of these names, put an option or `--` first:
`action-dag --no-open -- set`.

**The page opens only when it is new.** Without `--no-open`, the CLI opens
the page only if the file did not exist before the run. If the user already
has the page open, the CLI does not open a second tab. The open tab reloads
by itself (see [Keep the open page current](#keep-the-open-page-current)).

`--watch` prints one line per run: the count of nodes in each state, the
number of warnings and the number of changes. When a node changes state, it
also prints the full summary.

The summary has four parts:

- **Next for you**: the nodes in the `next` or `decide` state with the owner
  `me` or no owner. Each line has the link and the ask id.
- **WARNINGS**:
  - an MR with `hold_until` that is out of draft, approved or merged too
    early;
  - an MR that is closed without a merge;
  - an ask that is stale, dropped or not found;
  - a done node whose ask is still open ("tick the ask");
  - a failed lookup.
- **Changed since the last run**: each node whose state changed.
- **Waiting on others**: the nodes in the `wait` state.

Give the user the summary. Copy the URLs exactly as the CLI prints them.

## Edit the graph

**Use the editing commands. Do not edit the YAML file with the Edit tool.**

```bash
action-dag set  <goal> <node> [options]                  # change a node
action-dag add  <goal> <node> --title <t>                # add a node
action-dag edge <goal> <A> <B> [--remove]                # add or remove the edge [A, B]
action-dag done <goal> <node> --label <text> [--link <url>]  # move a finished node to the done row
action-dag rm   <goal> <node> [--force]                  # remove a node
```

Node options for `set` and `add`:

| Option | Effect |
|---|---|
| `--state next\|wait\|decide\|blocked\|done` | sets `status: {manual: <state>}` |
| `--status <source>` | replaces the status source. Give it more than once for a list of sources. Give `--status` or `--state`, not both. |
| `--pending <state>` | the state while a `--status probe:` fails (default `next`) |
| `--add-ask <id>` | adds an ask to `asks:` (you can give it more than once) |
| `--remove-ask <id>` | removes an ask from `asks:` (`set` only) |
| `--note <markdown>` | replaces `notes:` |
| `--append-note <text>` | adds the text on a new line at the end of `notes:` |
| `--title`, `--sub`, `--link`, `--owner`, `--lane`, `--hold-until <node>`, `--tag` | set that key |

An empty value removes the key: `--hold-until ''` or `--note ''`.

The values of `--status`:

| Value | YAML that it writes |
|---|---|
| `ask:<id>` | `{ask: <id>}` |
| `mr:<iid>` | `{mr: <iid>}`, with the project in `defaults` |
| `mr:<project>!<iid>` | `{mr: {project: <project>, iid: <iid>}}` |
| `mr:https://<host>/<project>/-/merge_requests/<iid>` | the short form if the host and the project are the same as in `defaults` |
| `probe:'<command>'` | `{probe: <command>}`. The command must be read-only. |
| `manual:<state>` | `{manual: <state>}` |

Options for `add`: `--side` adds a side track, with no lane. `--after <A>`
also adds the edge `[A, new node]`. `--before <B>` also adds the edge
`[new node, B]`. A new node gets `status: {manual: next}` if you do not give
a status. `--lane` is optional. With `--lane`, the command puts the new node
after the last node of that lane in the YAML file. Without `--lane`, it puts
the new node at the end of `nodes:`. The edges set the column of the node,
not the lane.

**`done`** moves a finished node to the `done:` row:

1. It reads the state of the node from its own sources (MR, ask, probe or
   manual). If the node is not done, the command stops. `--force` moves the
   node anyway.
2. It removes each edge to or from the node. Then it adds an edge from each
   predecessor of the node to each successor of the node. This keeps the
   order of the other steps.
3. It removes `hold_until: <node>` from the other nodes.
4. It adds `{label: <text>, link: <url>}` to the `done:` row. The default
   `<url>` is the link of the node.

**`rm`** removes a node. If an edge or a `hold_until` uses the node, the
command stops. `--force` also removes these edges and `hold_until` keys. It
does not add edges between the predecessors and the successors (`done` does).

Each editing command:

- keeps the comments, the key order, the quotes and the blank lines of the
  file. Only the lines of the change are different.
- checks the result as `--check` does. If the result has an error (for
  example a cycle, or a lane that is not in `lanes:`), the command writes
  nothing and exits with code 1. It prints the new warnings, for example a
  probe that possibly writes.
- writes the YAML file atomically (a temporary file, then a rename), and
  prints a one-line summary of the change.
- then writes the page and the state file again, and prints the summary, as
  `action-dag <goal> --no-open` does. It never opens a browser tab.

Two options for each editing command:

- `--dry-run`: print the change as a unified diff. Write nothing.
- `--no-render`: write the YAML file, but not the page. Use it for a series
  of edits. Then run `action-dag <goal> --no-open` one time at the end.

Examples, for the graph in [YAML schema](#yaml-schema):

```bash
action-dag set  example-cutover B --add-ask ef56
action-dag set  example-cutover D --state done --append-note "Decided: keep the old cluster for 7 days."
action-dag set  example-cutover A --status mr:42 --no-render
action-dag add  example-cutover E --title "Delete the old cluster" --after D --link https://gitlab.example.com/group/repo/-/issues/9
action-dag edge example-cutover B D
action-dag done example-cutover B --label "!41 migration"
action-dag rm   example-cutover S1 --dry-run
```

## The page

- **On each run, the CLI calculates the columns from the state of each
  node.** From left to right:

  | Column | Cards |
  |---|---|
  | **Done** | the nodes in the `done` state. These cards are small and dim. |
  | **Ready now** | the open steps with all predecessors done (or no predecessors) |
  | **After 1 step**, **After 2 steps**, ... | the open steps with open steps before them |

  N in "After N steps" is the number of open steps on the longest path of
  open predecessors. The count stops at a done step. Example: for the open
  steps A → B → C, A is in Ready now, B is in After 1 step, and C is in After
  2 steps.
- A card in Ready now can still wait for a review or a decision (the `wait`
  or `decide` state).
- When a step becomes done, the steps after it move to the left on the next
  run. You do not move them.
- The page does not show a column that has no cards. In a column, the cards
  are in the order of the YAML file.
- The YAML `lanes:` and `lane:` do not change the columns. The detail panel
  shows the lane of a node as a small "Lane: ..." line.
- Most arrows go from left to right. An arrow between two Done cards goes up
  or down in the Done column. An arrow goes to the left only to a Done card
  whose predecessor is not done.
- Each card is a button. Click it, or press Enter or Space on it, to open the
  **detail panel**. On a wide screen, the panel is on the right side. On a
  narrow screen, it is below the board. Escape or the Close button closes it.
- The selected card has a highlight. Its edges show in the accent colour. The
  other edges are dim.
- When you select a card, each card that has an arrow to it or from it gets
  a thin outline in the accent colour.
- The panel shows the **chain** of the selected card: all the steps before
  it and all the steps after it, directly or through other steps. It shows
  them as small cards with arrows. The steps before it are in rows above it,
  and the steps after it are in rows below it. The row of a step is the
  number of arrows on the longest path from the selected card, so each arrow
  points down. Click a small card to select that step. The board then
  scrolls to show its card. A card with no arrows (for example, a side track)
  has no chain.
- The panel shows:
  - **Every node**: the state, the warnings, the `notes:` text, and one
    button for each link. "Waits on" and "Unblocks" show the predecessors and
    the next nodes as small buttons (chips). Click a chip to select that node.
  - **Ask**: the ask note as HTML (title, Why, Do this, Done when), its state,
    its age and the note path. Each code block has a **Copy** button.
  - **MR**: the title, state, draft, approvals, head pipeline status, and the
    **Open MR** and **Open pipeline** buttons.
  - **Probe**: the command and its last result: the exit code, and the end of
    stderr if the probe failed.
  - **Manual**: the state as written, and the `notes:` text.
- Links open in a new tab. Only full `https://` URLs become buttons.
- The page is one static file. The CLI puts all the panel content in the page
  when it writes it, so the page works from `file://` and as an Artifact. The
  only external request is for [Google Fonts](https://fonts.google.com/).

## Keep the open page current

- JavaScript in the page reloads it every `refresh_seconds` (default 60; `0`
  turns it off). If the browser does not run JavaScript, a
  [`<meta http-equiv="refresh">`](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/meta#http-equiv)
  tag in `<noscript>` reloads the page.
- The URL hash holds the selected node, for example `#C1`.
  [`sessionStorage`](https://developer.mozilla.org/en-US/docs/Web/API/Window/sessionStorage)
  also holds it, so the node stays selected if a reload removes the hash.
  After a reload, the page opens the panel of that node again.
- The page keeps the scroll positions in `sessionStorage`, so a reload does
  not move the view.
- A reload shows only the data of the last run. To get new data, run
  `action-dag <goal> --watch` in a terminal. The page cannot get new data by
  itself, because browsers block fetch requests from `file://` pages.
- The page shows the time of the last run ("Generated ..."). Use it to see
  how old the data is.

## How the CLI finds the status of a node

Each node has a `status:` source. The CLI reads all the sources in parallel.
A failed lookup does not stop the run: that node shows `unknown`, and the
panel shows the error.

| Source | Done when | Not done |
|---|---|---|
| `mr: <iid>` or `mr: {project, iid, host}` | the MR is merged | draft or not approved → `wait`; approved, or CI failed → `next`; closed → `unknown` |
| `ask: <id>` | the ask is ticked | open → `next`, with a stale warning after `ASK_STALE_DAYS` days (default 7); dropped → `unknown` |
| `probe: <sh command>` | the command exits 0 in 8 s or less | the `pending:` state (default `next`); time-out → `unknown` |
| `manual: next\|wait\|decide\|blocked\|done` | `done` | as written |

You can give a list of sources. The node is done when **one** of the sources
is done. If no source is done, the first source sets the state.

Then the CLI applies the predecessors:

1. A node that is done stays done.
2. A node with a predecessor that is not done is `blocked`.
3. A node whose predecessors are all done keeps the state of its source.

**`hold_until: <node id>`** on an MR node gives a warning when the MR is out
of draft, approved or merged while that other node is not done. Use it for an
MR that must not merge before a cutover step.

`asks: [id, ...]` shows related asks on the card and in the panel. These asks
add only the stale and dropped warnings. They do not set the state.

## Probes must be read-only

**A probe must never change anything.** The CLI runs every probe on every
run, and `--watch` runs them again and again. Use `ls`, `describe`, `get`,
`glab api` GET requests and `test`. Do not use `apply`, `create`, `delete`, a
redirect into a file, or `ask-zk done`. The CLI cannot stop a probe that
writes. `--check` warns about a probe that looks like it writes, but this
check does not find every write.

A probe runs through `/bin/sh` with a time-out of 8 s. A probe that needs
credentials sets them in the command, for example `CLOUDSDK_CONFIG=... gcloud
...`. If the credentials expire, the probe fails and the node does not show
done. The panel shows the end of stderr.

## Secrets

An ask note must never hold a secret. As a second protection, the CLI
replaces text that looks like a token with `[REDACTED]` before it puts the
text in the page: GitLab tokens (`glpat-`, `gldt-`, `gloas-` and the other
`gl...-` prefixes), GitHub and Slack tokens, Google access tokens (`ya29.`),
a long value after `Bearer `, and a long value after `TOKEN=`, `SECRET=`,
`PASSWORD=` or `PRIVATE...=`. This applies to ask notes, `notes:`, probe
stderr and MR titles. It cannot find every secret. If a secret is in a note,
remove it from the note and rotate it.

## YAML schema

```yaml
goal: example-cutover                 # same as the file name
title: Example Cutover Map
summary: "The service runs on the new cluster."
output: example-cutover.dag.html      # optional. Relative to the YAML file's directory
refresh_seconds: 60                   # optional. 0 turns off the browser reload
defaults:                             # used by each `mr:` that has only an iid
  mr_host: gitlab.example.com
  mr_project: group/repo
lanes:                                # optional labels. They do not change the columns
  - {id: now, title: "Now, in parallel"}
  - {id: cutover, title: "Cutover"}
nodes:
  - id: A
    lane: now                         # optional. The panel shows "Lane: <title>"
    title: Apply the database unit
    sub: "Expect 3 to add, 0 to destroy"
    link: https://gitlab.example.com/group/repo/-/tree/main/db
    owner: me                         # me | a name | empty
    status:
      - ask: ab12
      - probe: "gcloud sql instances describe db-1 >/dev/null 2>&1"
        pending: wait                 # state while the probe fails (default next)
  - id: B
    title: Merge the migration MR
    status: {mr: 41}                  # the MR link becomes the "Open MR" button
    asks: [cd34]
  - id: C
    lane: cutover
    tag: runbook 2                    # extra text in the card's id row
    title: Switch the backend
    status: {mr: {project: group/other, iid: 7, host: gitlab.example.com}}
    hold_until: A
    links:                            # panel buttons, in addition to `link`
      - {label: "Open runbook", url: "https://gitlab.example.com/group/repo/-/blob/main/runbook.md"}
  - id: D
    lane: cutover
    title: Choose the rollback rule
    owner: me
    status: decide                    # short form of {manual: decide}
    notes: |                          # markdown, shown in the panel
      Keep the old cluster for 7 days, or delete it at once?
      The user decides.
edges:                                # [before, after]
  - [A, C]
  - [B, C]
  - [C, D]
done:                                 # the row of finished work under the board
  - {label: "!40 bucket", link: "https://gitlab.example.com/group/repo/-/merge_requests/40"}
side:                                 # nodes that are not on the path. No lane, no edges
  - id: S1
    title: Rotate the leaked token
    link: https://gitlab.example.com/-/user_settings/personal_access_tokens
    status: {ask: ef56}
```

A bare `link:` gets a button label from its URL: "Open MR", "Open job",
"Open pipelines", "Open file", "Open directory", "Open issue" or "Open link".
Use `links:` to set the label yourself.

## Make a graph for a new goal

1. Find the hub note of the goal (load the `zk` skill). If there is no hub
   note, make one first.
2. Write the first version of `<notebook>/<goal>.dag.yaml`. Use the spoke
   notes of the hub note, the open MRs and the open asks
   (`ask-zk --plain --no-verify list --tag <topic>`). After the first version,
   use the [editing commands](#edit-the-graph).
3. Give each node the best source that a machine can read: an MR, then an
   ask, then a read-only probe. Use `manual:` only for a decision or for a
   step that nothing can observe.
4. For each decision, write the open question in `notes:`: the options, and
   who decides.
5. Put a full `https://` link on each node. A node with an `mr:` source gets
   the MR link automatically.
6. Write an edge for each "must finish before" relation. The edges and the
   node states set the columns, so you do not need `lanes:`. Use `lane:` only
   as a label for the detail panel.
7. Run `action-dag <goal> --check` until it shows `0 errors`.
8. Run `action-dag <goal> --no-open` and give the user the summary.
9. Link the hub note to the files. zk does not index YAML or HTML, so use
   plain markdown links, not wiki links:
   `[Action graph](<goal>.dag.html) ([source](<goal>.dag.yaml))`.

## Update a graph when the facts change

The live sources update by themselves. When a step becomes done, the next
run moves its card to the Done column and moves the steps after it to the
left. Do not move nodes by hand. Change the graph only when the structure or
a manual fact changes. Use the [editing commands](#edit-the-graph):

- **A decision is made**:
  `action-dag set <goal> <node> --state done --append-note "<the result>"`.
- **A new step**: `action-dag add <goal> <node> --title <t> --after <A>`,
  then `action-dag edge` for each other edge.
- **A manual step now has an MR or an ask**:
  `action-dag set <goal> <node> --status mr:<iid>` (or `ask:<id>`).
- **A step is finished and old** (optional cleanup): `action-dag done
  <goal> <node> --label "<text>"`. This removes the card from the Done
  column and adds a link to the done row.
- **An ask was dropped or an MR was closed**: the CLI shows a warning. Give
  the node a new source with `set --status`, or remove the node with `rm`.
- **The goal is complete or stopped**: run the CLI one last time, so the page
  shows the final state. Then write a line in the hub note. Keep the files as
  a record.

Each editing command writes the page again and prints the summary. Give the
user the summary. After a series of `--no-render` edits, run
`action-dag <goal> --no-open` one time.

## Share the page

**For each page that leaves this machine (an Asana attachment, Slack, email
or an Artifact), use `--public`.** The normal page contains the ask notes and
local paths.

```bash
action-dag <goal> --public [--output <file>] [--redact-pattern '<regex>' ...]
```

The public page:

- has no ask data: no ask panels, no ask ids on the cards, no `asks:` lists
  and no ask warnings. A node with an ask source keeps the state that the
  ask gives. Its detail line says only "private note open" (or `closed`,
  `not found`, `was dropped`).
- replaces each local path with `[local path]`: a path under the home
  directory, `/Users/<name>/…`, `/home/<name>/…`, `~/…`, `$HOME/…`.
- replaces each zk wiki link with its label: `[[id|label]]` becomes `label`,
  and `[[id]]` is removed.
- removes each match of each `--redact-pattern` (a Python regular
  expression; give the option more than once for more patterns). The
  patterns apply to titles, subtitles, notes, details, warnings, MR titles
  and probe text, but not to URLs, so the links still work. Use them for bare
  note ids and commit hashes. The CLI cannot find these by itself.
- does not reload in the browser, and shows no "changed since the last run"
  marks.

`--public` never reads or writes the state file. It never opens the page. It
writes the normal page only if `--output` names that file.

Before it writes, the CLI checks the page. If the page still contains the
home directory path, `~/` or `[[`, the CLI writes nothing and exits with
code 1. Otherwise it prints the number of items it removed of each type,
and then the page path.

The check does not find all private text. For example, it does not find an
email address or a note id with no brackets. Read the public page before you
share it.

In a session with a claude.ai login, you can publish the public page with the
Artifact tool. Publish it again after each run, from the same file path, so
the URL stays the same.

## Rules

- The CLI calls ask-zk with `--no-verify` only. Never run `ask-zk done` or
  `ask-zk drop` because of what the graph shows. Only the user ticks an ask.
- The CLI calls glab with GET requests only. It never prints a token.
- Do not edit `<goal>.dag.yaml` with the Edit tool. Use the editing commands.
  They keep the layout of the file and refuse to write a graph with errors.
- Tests: `uv run --script home-manager/bin/tests/test_action_dag.py` in the
  nixfiles repo.
