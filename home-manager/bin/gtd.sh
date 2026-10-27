#!/usr/bin/env bash
# gtd — GTD Flow (Obsidian plugin) from the terminal.
#
#   gtd                      Fuzzy-pick a perspective or tag (live preview); prints its tasks
#   gtd ls <name|#tag>       Print a perspective's tasks, or the available tasks with a tag
#   gtd next                 Print next actions: the inbox, then each active project
#   gtd add <text...>        Append "- [ ] <text>" to the GTD Flow inbox note
#   gtd open <name>          Show a saved perspective in Obsidian
#
# In the picker, ctrl-o opens the highlighted perspective in Obsidian.
#
# Everything goes through the Obsidian CLI (Settings > General > Advanced >
# Command line interface), so Obsidian must be running; the first call starts it.
# Tasks come from GTD Flow's own index, which parses the notes. Which tasks are
# available (sequential projects, 🛫 defer dates, ⛔ dependencies, #someday) and
# how perspectives filter are copied from GTD Flow 0.9.7's engine.ts and
# perspectives.ts, because the plugin doesn't export them. Recheck after
# updating GTD Flow.
#
# Override the CLI binary with OBSIDIAN_CLI, and the vault with GTD_VAULT.

set -euo pipefail

# The Obsidian CLI turns \n and \t in values into newlines and tabs, so this
# JavaScript avoids backslashes (String.fromCharCode instead) and `//` comments,
# because its newlines are joined into one line before it is sent.
read -r -d '' JS <<'EOF' || true
(async () => {
const Q = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob("__QUERY__"), c => c.charCodeAt(0))));
const g = app.plugins.plugins["gtd-flow"];
if (!g) return "ERR GTD Flow isn't enabled in this vault";
const S = g.settings, NL = String.fromCharCode(10), TAB = String.fromCharCode(9);
const now = new Date();
const today = new Date(now - now.getTimezoneOffset() * 6e4).toISOString().slice(0, 10);
const addDays = (iso, n) => { const d = new Date(iso + "T00:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const projects = g.index.snapshot();
const label = p => p.path === S.inboxNote ? "Inbox" : (p.label ?? p.name);
const someday = S.somedayTag || "someday";
const isSomeday = t => t.tags.includes(someday);
const byId = new Map();
for (const p of projects) for (const t of p.tasks) if (t.id) { if (!byId.has(t.id)) byId.set(t.id, []); byId.get(t.id).push(t); }
const waiting = t => (t.blockedBy || []).some(id => id !== t.id && (byId.get(id) || []).some(b => !b.done));
const tree = tasks => {
  const roots = [], stack = [];
  for (const t of tasks) {
    const n = { task: t, children: [] };
    while (stack.length && stack[stack.length - 1].task.indent >= t.indent) stack.pop();
    (stack.length ? stack[stack.length - 1].children : roots).push(n);
    stack.push(n);
  }
  return roots;
};
const flowOf = (t, f) => t.tags.includes("sequential") ? "sequential" : t.tags.includes("parallel") ? "parallel" : f;
const collect = (nodes, flow, out) => {
  let blocked = false;
  for (const n of nodes) {
    const t = n.task, deferred = (!!t.defer && t.defer > today) || waiting(t), sd = isSomeday(t);
    if (!t.done && !sd && !blocked && !deferred) {
      if (n.children.some(c => !c.task.done)) collect(n.children, flowOf(t, flow), out);
      else out.push(t);
    }
    if (flow === "sequential" && !t.done && !sd) blocked = true;
  }
};
const available = p => { if (p.status !== "active") return []; const out = []; collect(tree(p.tasks), p.flow, out); return out; };
const tagMatches = (tags, f) => tags.some(t => t === f || t.startsWith(f + "/"));
const inFolder = (path, folder) => { const f = folder.replace(/^[/]+|[/]+$/g, "").toLowerCase(); if (!f) return true; const p = path.toLowerCase(); return p.startsWith(f + "/") || p.includes("/" + f + "/"); };
const run = p => {
  const mode = p.somedayMode ?? (p.someday ? "only" : "exclude");
  const horizon = p.dueWithin > 0 ? addDays(today, p.dueWithin) : "";
  const since = p.done && p.dueWithin > 0 ? addDays(today, -p.dueWithin) : "";
  const items = [];
  for (const pr of projects) {
    if (p.project && !pr.name.toLowerCase().includes(p.project.toLowerCase())) continue;
    if (p.folder && !inFolder(pr.path, p.folder)) continue;
    const open = pr.tasks.filter(t => !t.done);
    let pool;
    if (p.done) pool = pr.tasks.filter(t => t.done);
    else {
      const active = pr.status === "active";
      let act = active ? open.filter(t => !isSomeday(t)) : [];
      if (p.availableOnly) { const av = new Set(available(pr)); act = act.filter(t => av.has(t)); }
      const parked = mode === "exclude" ? [] : pr.status === "someday" ? open : active ? open.filter(isSomeday) : [];
      pool = mode === "only" ? parked : [...act, ...parked];
    }
    for (const t of pool) {
      if (p.flagged && !t.tags.includes(S.flagTag)) continue;
      if (p.important && !t.tags.includes(S.importantTag)) continue;
      if (p.tag && !tagMatches(t.tags, p.tag)) continue;
      if (p.dueWithin > 0) {
        if (p.done) { const c = t.completedOn ?? t.cancelledOn; if (!c || c < since) continue; }
        else if (!t.due || t.due > horizon) continue;
      }
      items.push({ pr, t });
    }
  }
  return items;
};
const fmt = (t, pr) => {
  let s = "- " + (t.done ? "[x] " : t.inProgress ? "[/] " : "[ ] ") + t.text;
  if (t.tags.length) s += "  " + t.tags.map(x => "#" + x).join(" ");
  if (t.due) s += (t.due < today ? "  📅 " + t.due + " OVERDUE" : "  📅 " + t.due);
  if (pr) s += "  (" + label(pr) + ")";
  return s;
};
const groups = (items, by) => {
  const m = new Map(), add = (k, it) => { if (!m.has(k)) m.set(k, []); m.get(k).push(it); };
  for (const it of items) {
    if (by === "project") add(label(it.pr), it);
    else if (by === "due") add(it.t.due ?? "no due date", it);
    else {
      const roots = new Set(it.t.tags.filter(x => x !== S.flagTag && x !== S.importantTag && x !== "sequential" && x !== "parallel").map(x => x.split("/")[0]));
      if (!roots.size) add("untagged", it); else for (const r of roots) add("#" + r, it);
    }
  }
  return [...m.entries()].sort((a, b) => a[0].localeCompare(b[0]));
};
const render = (gs, by) => gs.length === 0 ? "Nothing matches." : gs.map(([k, its]) => "## " + k + NL + its.map(it => fmt(it.t, by === "project" ? null : it.pr)).join(NL)).join(NL + NL);
const resolve = name => {
  if (name.startsWith("#")) return { name, availableOnly: true, tag: name.slice(1), dueWithin: 0, groupBy: "project" };
  return S.perspectives.find(p => p.name === name) ?? S.perspectives.find(p => p.name.toLowerCase() === name.toLowerCase());
};
if (Q.cmd === "choices") {
  const tags = new Set();
  for (const pr of projects) if (pr.status === "active") for (const t of pr.tasks) if (!t.done) for (const x of t.tags) tags.add("#" + x);
  return [...S.perspectives.map(p => p.name), ...[...tags].sort()].join(NL);
}
if (Q.cmd === "ls") {
  const p = resolve(Q.name);
  if (!p) return "ERR no perspective named " + Q.name;
  return render(groups(run(p), p.groupBy), p.groupBy);
}
if (Q.cmd === "next") {
  const out = [];
  for (const pr of [...projects].sort((a, b) => (a.path === S.inboxNote ? -1 : b.path === S.inboxNote ? 1 : label(a).localeCompare(label(b))))) {
    const av = available(pr);
    if (av.length) out.push("## " + label(pr) + NL + av.map(t => fmt(t)).join(NL));
    else if (pr.status === "active" && pr.path !== S.inboxNote) out.push("## " + label(pr) + "  (stalled: nothing available)");
  }
  return out.length ? out.join(NL + NL) : "Nothing available.";
}
if (Q.cmd === "add") {
  const line = "- [ ] " + Q.text + NL;
  const f = app.vault.getFileByPath(S.inboxNote);
  if (!f) await app.vault.create(S.inboxNote, line);
  else await app.vault.process(f, c => (c && !c.endsWith(NL) ? c + NL : c) + line);
  return "Added to " + S.inboxNote;
}
if (Q.cmd === "open") {
  const p = resolve(Q.name);
  if (!p || Q.name.startsWith("#")) return "ERR no saved perspective named " + Q.name + " (tags can only be printed, not opened)";
  await g.activateView("gtd-perspectives");
  const leaf = app.workspace.getLeavesOfType("gtd-perspectives")[0];
  if (!leaf) return "ERR couldn't open the Perspectives view";
  leaf.view.selected = p.name;
  leaf.view.render();
  return "Opened " + p.name;
}
return "ERR unknown command";
})()
EOF

cli=()
if [[ -n ${OBSIDIAN_CLI:-} ]]; then
  cli=("$OBSIDIAN_CLI")
elif command -v obsidian >/dev/null 2>&1; then
  cli=(obsidian)
elif [[ -x /Applications/Obsidian.app/Contents/MacOS/obsidian-cli ]]; then
  cli=(/Applications/Obsidian.app/Contents/MacOS/obsidian-cli)
else
  echo "gtd: can't find the Obsidian CLI; set OBSIDIAN_CLI" >&2
  exit 1
fi
[[ -n ${GTD_VAULT:-} ]] && cli+=("vault=$GTD_VAULT")

# query <json>: run JS with the query and print its result, failing on errors.
query() {
  local b64 out
  b64=$(printf '%s' "$1" | base64 | tr -d '\n')
  out=$("${cli[@]}" eval "code=$(printf '%s' "${JS//__QUERY__/$b64}" | tr '\n' ' ')" 2>&1) || {
    echo "gtd: $out" >&2
    return 1
  }
  case $out in
  "=> ERR "*)
    echo "gtd: ${out#=> ERR }" >&2
    return 1
    ;;
  "=> "*) printf '%s\n' "${out#=> }" ;;
  *)
    echo "gtd: $out" >&2
    return 1
    ;;
  esac
}

usage() {
  cat <<'USAGE'
gtd                      Fuzzy-pick a perspective or tag (live preview); prints its tasks
gtd ls <name|#tag>       Print a perspective's tasks, or the available tasks with a tag
gtd next                 Print next actions: the inbox, then each active project
gtd add <text...>        Append "- [ ] <text>" to the GTD Flow inbox note
gtd open <name>          Show a saved perspective in Obsidian
USAGE
}

cmd=${1:-pick}
[[ $# -gt 0 ]] && shift
case $cmd in
pick)
  self=$(command -v gtd || echo "$0")
  choice=$(query '{"cmd":"choices"}' | fzf --prompt 'gtd> ' \
    --preview "$self ls {}" --preview-window 'right,65%,wrap' \
    --bind "ctrl-o:execute-silent($self open {})") || exit 0
  query "$(jq -n --arg n "$choice" '{cmd:"ls",name:$n}')"
  ;;
ls) query "$(jq -n --arg n "${1:?usage: gtd ls <perspective|#tag>}" '{cmd:"ls",name:$n}')" ;;
next) query '{"cmd":"next"}' ;;
add)
  [[ $# -gt 0 ]] || { echo "usage: gtd add <text...>" >&2; exit 1; }
  query "$(jq -n --arg t "$*" '{cmd:"add",text:$t}')"
  ;;
open) query "$(jq -n --arg n "${1:?usage: gtd open <perspective>}" '{cmd:"open",name:$n}')" ;;
-h | --help | help) usage ;;
*)
  usage >&2
  exit 1
  ;;
esac
