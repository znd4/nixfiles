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
- **Lane**: a column of cards. Lanes go from left to right.
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
  and no edges.
- **Done row**: a row of links to finished work, under the board.
- **Artifact**: a web page on claude.ai that the Artifact tool publishes.

## Files

The files are in the zk notebook, next to the hub note of the goal. The
notebook is `$ACTION_DAG_NOTEBOOK`. The default is the ask-zk notebook.

| File | Written by | Contents |
|---|---|---|
| `<goal>.dag.yaml` | you, by hand | the graph: lanes, nodes, edges, status sources |
| `<goal>.dag.html`, or the `output:` path | `action-dag` | the page. Each run writes it again. Do not edit it. |
| `<goal>.dag.state.json` | `action-dag` | the state of each node at the last run. It is always next to the YAML file. |

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
```

`<goal>` is the file name without `.dag.yaml`.

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

## The page

- Each card is a button. Click it, or press Enter or Space on it, to open the
  **detail panel**. On a wide screen, the panel is on the right side. On a
  narrow screen, it is below the board. Escape or the Close button closes it.
- The selected card has a highlight. Its edges show in the accent colour. The
  other edges are dim.
- When you select a card, each card that has an arrow to it or from it gets
  a thin outline in the accent colour.
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
lanes:                                # columns, from left to right
  - {id: now, title: "Now, in parallel", sub: "Prerequisites"}
  - {id: cutover, title: "Cutover", align: center}   # center: center the cards vertically
nodes:
  - id: A
    lane: now
    title: Apply the database unit
    sub: "Expect 3 to add, 0 to destroy"
    link: https://gitlab.example.com/group/repo/-/tree/main/db
    owner: me                         # me | a name | empty
    status:
      - ask: ab12
      - probe: "gcloud sql instances describe db-1 >/dev/null 2>&1"
        pending: wait                 # state while the probe fails (default next)
  - id: B
    lane: now
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
2. Write `<notebook>/<goal>.dag.yaml`. Use the spoke notes of the hub note,
   the open MRs and the open asks
   (`ask-zk --plain --no-verify list --tag <topic>`).
3. Give each node the best source that a machine can read: an MR, then an
   ask, then a read-only probe. Use `manual:` only for a decision or for a
   step that nothing can observe.
4. For each decision, write the open question in `notes:`: the options, and
   who decides.
5. Put a full `https://` link on each node. A node with an `mr:` source gets
   the MR link automatically.
6. Run `action-dag <goal> --check` until it shows `0 errors`.
7. Run `action-dag <goal> --no-open` and give the user the summary.
8. Link the hub note to the files. zk does not index YAML or HTML, so use
   plain markdown links, not wiki links:
   `[Action graph](<goal>.dag.html) ([source](<goal>.dag.yaml))`.

## Update a graph when the facts change

The live sources update by themselves. Edit the YAML only when the structure
or a manual fact changes:

- **A decision is made**: change `manual: decide` to `manual: done`, and write
  the result in `notes:`.
- **A new step**: add a node and its edges. Run `--check`.
- **A manual step now has an MR or an ask**: change its `status:` to the
  `mr:` or `ask:` source.
- **A step is finished and old**: move it from `nodes` to the `done` row, and
  move its edges to the next node.
- **An ask was dropped or an MR was closed**: the CLI shows a warning. Give
  the node a new source, or remove the node.
- **The goal is complete or stopped**: run the CLI one last time, so the page
  shows the final state. Then write a line in the hub note. Keep the files as
  a record.

After each edit, run `action-dag <goal> --no-open` and give the user the
summary.

## Share the page

In a session with a claude.ai login, you can publish the page with the
Artifact tool. Read the page before you publish it. Publish it again after
each run, from the same file path, so the URL stays the same.

## Rules

- The CLI calls ask-zk with `--no-verify` only. Never run `ask-zk done` or
  `ask-zk drop` because of what the graph shows. Only the user ticks an ask.
- The CLI calls glab with GET requests only. It never prints a token.
- Tests: `uv run --script home-manager/bin/tests/test_action_dag.py` in the
  nixfiles repo.
