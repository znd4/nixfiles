{
  inputs,
  system,
  pkgs,
  lib,
  seshClConfig,
  ...
}:
let
  herdr = inputs.herdr.packages.${system}.default;

  # Same build television.nix pins, so the launcher below cannot drift onto a
  # different `tv` than the one the rest of the config is configured for.
  television = inputs.nixpkgs-unstable.legacyPackages.${system}.television;

  workDir = "$HOME/Work";
  # Same directory for TOML, where $HOME does not expand. herdr resolves a
  # leading ~ in path-valued settings itself.
  workDirTilde = "~/Work";

  # Flake ref for an arbitrary herdr release tag. herdr-handoff below uses it
  # only as a fallback, to materialize a CLI matching the running server when
  # that server's own executable cannot be found. Keep the repo in sync with the
  # `herdr` input in ../../flake.nix by hand: flake inputs are a static attrset,
  # so the URL cannot be shared from here.
  herdrFlakeRefFor = tag: "git+ssh://git@github.com/herdrdev/herdr.git?shallow=1&ref=refs/tags/${tag}#default";

  # Upgrade the running herdr server in place, without exiting pane processes.
  #
  # A plain `herdr server stop` kills every pane, which is a bad trade for a
  # version bump. herdr instead supports `server live-handoff`: the old server
  # serializes its session snapshot and passes the pane PTY file descriptors
  # over a unix socket to a newly spawned server, so terminals, agents, and
  # scrollback all survive the swap.
  #
  # The panes survive; the attached client does NOT. The TUI exits with the old
  # server and has to be relaunched by hand — upstream has no reattach path, so
  # `herdr update --handoff` behaves the same way. Measured on a 41-pane session:
  # the swap took 262ms and every pane process lived, but the window went away
  # until `herdr` was run again. Hence the warning and the confirmation below.
  #
  # The handoff has to be driven by a CLI the *running* server understands. The
  # new CLI does send this one request via `send_request_unchecked`, ducking the
  # usual protocol guard, but only a version-matched CLI is guaranteed to
  # serialize a request an older server can still parse.
  #
  # The version-matched CLI is already on disk: herdr ships ONE binary for both
  # the server and the CLI, so the running server's own executable is, by
  # construction, a CLI that matches it exactly. Read it out of the process
  # table and use it — no rebuild, no second flake input, and correct even for a
  # build that was never tagged. Building `refs/tags/v$server_version` stays as
  # the fallback for a server whose executable cannot be located.
  #
  # That store path is also the only reliable build identity here. `herdr
  # status` reports the crate version and nothing else, and an off-tag rev
  # (flake.nix currently pins one for the ctrl+click double-open fix) still
  # reports the version of the release it was cut from — so a version compare
  # answers "nothing to do" for a genuine upgrade. Compare store paths instead.
  herdrHandoff = pkgs.writeShellApplication {
    name = "herdr-handoff";
    runtimeInputs = [
      pkgs.jq
      pkgs.gawk
      pkgs.coreutils
    ];
    # `nix` is deliberately not a runtimeInput: writeShellApplication only
    # prepends to PATH, so the ambient nix (matching the running daemon) wins.
    text = ''
      new_exe="${herdr}/bin/herdr"
      status_json=$("$new_exe" status --json)

      running=$(jq -r '.server.running' <<<"$status_json")
      if [ "$running" != "true" ]; then
        echo "no herdr server running -- nothing to hand off. Just start herdr."
        exit 0
      fi

      server_version=$(jq -r '.server.version' <<<"$status_json")
      new_version=$(jq -r '.client.version' <<<"$status_json")
      new_protocol=$(jq -r '.client.protocol' <<<"$status_json")

      # argv[0] of the running server process: the store path of the binary the
      # server is executing. `herdr server` is how every server is spawned,
      # including one that arrived through a previous --handoff-import. -ww
      # because ps otherwise truncates the argv column to the terminal width,
      # and a store path plus the handoff arguments overruns a narrow one.
      server_exe=$(ps -A -ww -o args= 2>/dev/null \
        | awk '/\/bin\/herdr[[:space:]]+server([[:space:]]|$)/ { print $1; exit }' \
        || true)

      if [ -n "$server_exe" ]; then
        if [ "$server_exe" = "$new_exe" ]; then
          echo "server already runs the installed build (herdr $new_version) -- nothing to do."
          exit 0
        fi
      elif [ "$server_version" = "$new_version" ]; then
        # No executable to compare against, so the version string is all there
        # is. It cannot distinguish two builds of the same version; say so
        # rather than claiming the server is up to date.
        echo "could not read the running server's executable from the process table," >&2
        echo "and it reports the same version ($new_version) as the installed build." >&2
        echo "Nothing to compare -- not handing off. Restart herdr to be certain." >&2
        exit 1
      fi

      if [ "$(jq -r '.server.capabilities.live_handoff' <<<"$status_json")" != "true" ]; then
        echo "running server does not advertise live_handoff; it can only be" >&2
        echo "replaced by a restart, which exits every pane process." >&2
        exit 1
      fi

      pane_count=$("$new_exe" workspace list 2>&1 \
        | jq -r '[.result.workspaces[].pane_count] | add // "?"')

      if [ "$server_version" = "$new_version" ]; then
        echo "herdr $new_version -> $new_version (same version, different build)"
        echo "  running:   $server_exe"
        echo "  installed: $new_exe"
      else
        echo "herdr $server_version (running) -> $new_version (installed)"
      fi
      echo
      echo "  $pane_count pane processes keep running across the swap."
      echo "  This herdr WINDOW will close. Run 'herdr' again to reattach --"
      echo "  the panes are all still there, they just have no viewer."
      echo
      case "''${1-}" in
        -y | --yes) ;;
        *)
          if [ ! -t 0 ]; then
            echo "stdin is not a terminal; pass --yes to confirm." >&2
            exit 1
          fi
          printf 'continue? [y/N] '
          read -r reply || reply=""
          case "$reply" in
            y | Y | yes | YES) ;;
            *)
              echo "aborted; nothing changed."
              exit 0
              ;;
          esac
          ;;
      esac

      if [ -n "$server_exe" ]; then
        old_exe="$server_exe"
      else
        echo "building the herdr $server_version CLI to match the running server..."
        old_exe=$(nix build --no-link --print-out-paths "${herdrFlakeRefFor "v$server_version"}")/bin/herdr
      fi

      # --expected-* make the import fail closed: the new server verifies it is
      # really the build we intended before the old one commits, and the old
      # server rolls back and keeps serving if anything does not line up.
      exec "$old_exe" server live-handoff \
        --import-exe "$new_exe" \
        --expected-version "$new_version" \
        --expected-protocol "$new_protocol"
    '';
  };

  # seshClConfig (gitlabHosts / githubOrgs / parentDirectories) is the same
  # config the tmux clone popup consumes; rendered into nuon list literals for
  # the clone-creator helper below.
  nuonList = xs: "[" + lib.strings.concatStringsSep " " xs + "]";

  # PR/MR review workflow, ported from the tmux `tmux-mr-review` popup: prompt
  # for a PR/MR URL, clone the repo if needed, check out the PR/MR as a worktree,
  # then open a herdr workspace laid out with a terminal (left) + tuicr on the
  # PR/MR (right). The logic lives in ../bin/herdr-mr-review.py (a `uv run`
  # script) so it gets real per-invocation logging (~/.local/state/herdr-mr-review/)
  # and can gain PyPI deps later via its inline metadata block. This wrapper just
  # puts the runtime tools + uv on PATH and execs it. `tuicr` is intentionally
  # not in runtimeInputs — it's provided on PATH by tuicr.nix and run from the
  # pane, the same call hunk got when it held that slot.
  herdrMrReview = pkgs.writeShellApplication {
    name = "herdr-mr-review";
    runtimeInputs = [
      pkgs.uv
      pkgs.git
      pkgs.coreutils
      pkgs.gh
      pkgs.glab
      pkgs.jq
      herdr
    ];
    text = ''
      exec uv run --script ${../bin/herdr-mr-review.py} "$@"
    '';
  };

  # Workspace/directory picker on alt+d, the descendant of the tmux `M-d`
  # sesh-connect popup. In tmux that fzf drove `sesh connect`, whose default tab
  # lists the live sessions first and the zoxide/find directories after them.
  # The herdr equivalent of a session is a workspace, so the default list is the
  # open workspaces followed by zoxide history: picking a workspace focuses it,
  # picking a directory opens it as a new workspace. Directory picks are
  # deduplicated against the open workspaces, matching `sesh connect`.
  #
  # It used to be an fzf popup with ^a/^w/^x/^f `reload(...)` tabs. It is now
  # television, which buys a preview panel worth having — a workspace previews
  # as its pane tree plus the live tail of its focused pane, a directory as its
  # git state, recent commits and contents. The four tabs became four cable
  # channels on alt-a/alt-w/alt-x/alt-f.
  #
  # The logic lives in ../bin/herdr-launcher so it stays shellcheck-able and
  # runnable on its own; see the header there for the entry format and why the
  # channels are generated at run time instead of via
  # `programs.television.channels`. It is inlined rather than exec'd so that $0
  # inside is this wrapper: tv re-invokes the script for every source and
  # preview, and those re-invocations need runtimeInputs on PATH.
  herdrLauncher = pkgs.writeShellApplication {
    name = "herdr-launcher";
    runtimeInputs = [
      television
      herdr
      pkgs.jq
      pkgs.fd
      pkgs.sesh
      pkgs.git
      pkgs.glow
      pkgs.gawk
      pkgs.gnused
      pkgs.findutils
      pkgs.coreutils
    ];
    text = ''
      export HERDR_WORK_DIR="''${HERDR_WORK_DIR:-${workDir}}"
    ''
    + builtins.readFile ../bin/herdr-launcher;
  };

  # Clone-creator, ported from the tmux `M-m` `_sesh-cl-fuzzy` popup. Same
  # gum/gh/glab repo picker across GitHub orgs, GitLab hosts, and a raw URL —
  # but instead of `sesh cl` (which spawns a tmux session) it clones into the
  # chosen parent dir under the ~/Work/{host}/{org}/{repo} layout and opens a
  # herdr workspace. Self-contained so no tmux is ever involved.
  herdrClone = pkgs.writeShellApplication {
    name = "herdr-clone";
    runtimeInputs = [
      pkgs.git
      pkgs.gum
      pkgs.gh
      pkgs.glab
      pkgs.jq
      pkgs.fzf
      pkgs.coreutils
      herdr
    ];
    text = ''
      gitlab_hosts=(${lib.strings.concatStringsSep " " (map (h: "'${h}'") seshClConfig.gitlabHosts)})
      github_orgs=(${lib.strings.concatStringsSep " " (map (o: "'${o}'") seshClConfig.githubOrgs)})

      # 1. Choose the source: GitHub, one of the GitLab hosts, or a raw URL.
      sources=("GitHub" "URL")
      for gh_host in "''${gitlab_hosts[@]}"; do sources+=("GitLab: $gh_host"); done
      source=$(printf '%s\n' "''${sources[@]}" | gum filter --header "Clone from where?") || exit 0
      [ -z "$source" ] && exit 0

      remote=""
      host="github.com"
      case "$source" in
        GitHub)
          host="github.com"
          repos=$( { gh repo list --json nameWithOwner --jq '.[].nameWithOwner' --limit 100000 2>/dev/null
                     for org in "''${github_orgs[@]}"; do
                       gh repo list "$org" --json nameWithOwner --jq '.[].nameWithOwner' --limit 100000 2>/dev/null
                     done
                   } | sort -u )
          sel=$(printf '%s\n' "$repos" | fzf --prompt 'github repo  ' --border) || exit 0
          [ -z "$sel" ] && exit 0
          remote="git@github.com:$sel.git"
          ;;
        URL)
          remote=$(gum input --placeholder "git clone URL (git@… or https://…)") || exit 0
          [ -z "$remote" ] && exit 0
          host=$(printf '%s' "$remote" | sed -E 's#^(git@\|https?://)##; s#[:/].*$##')
          ;;
        "GitLab: "*)
          host="''${source#GitLab: }"
          sel=$(GITLAB_HOST="$host" glab repo list --output json -P 1000 2>/dev/null \
                | jq -r '.[].path_with_namespace' \
                | fzf --prompt "gitlab repo ($host)  " --border) || exit 0
          [ -z "$sel" ] && exit 0
          remote="git@$host:$sel.git"
          ;;
      esac
      [ -z "$remote" ] && exit 0

      # 2. Derive the org/repo path from the remote and clone into the standard
      #    ~/Work/{host}/{org}/{repo} layout (matching the repo-directory convention).
      path=$(printf '%s' "$remote" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')
      repo_dir="${workDir}/$host/$path"
      if [ ! -d "$repo_dir" ]; then
        mkdir -p "$(dirname "$repo_dir")"
        git clone "$remote" "$repo_dir" || { echo "clone failed" >&2; exit 1; }
      fi

      herdr workspace create --cwd "$repo_dir" --label "$(basename "$path")" --focus
    '';
  };

  # New empty workspace with a prompted name, ported from the tmux `M-s`
  # new-session gum popup. herdr has a native `new_workspace` (prefix+shift+n)
  # that creates an unnamed workspace in the follow-cwd; this variant prompts
  # for a label first, matching the tmux muscle memory of naming up front.
  herdrNewNamed = pkgs.writeShellApplication {
    name = "herdr-new-named";
    runtimeInputs = [
      pkgs.gum
      pkgs.coreutils
      herdr
    ];
    text = ''
      name=$(gum input --placeholder "workspace name") || exit 0
      [ -z "$name" ] && exit 0
      # No --cwd: the server applies the `new_cwd` policy from config.toml
      # (~/Work), so this stays in step with every other unqualified new pane.
      herdr workspace create --label "$name" --focus
    '';
  };

  # herdr-thumbs: tmux-thumbs for herdr. Press prefix+space, every URL / path /
  # hash / IP on the focused pane gets a hint label; type the hint to copy it
  # (lowercase) or `open` it (UPPERCASE). Mirrors the old tmux-thumbs config
  # (@thumbs-upcase-command 'open {}', default action = copy to clipboard).
  #
  # Now a standalone flake (github:znd4/herdr-plugin-thumbs) rather than a
  # vendored copy: its default package is the assembled, PATH-wrapped plugin
  # directory, with passthru.pluginId = "znd4.thumbs". Its herdr input follows
  # ours (see flake.nix), so the `herdr` on the launcher's PATH matches the
  # server. Linked at activation below; bound to prefix+space further down.
  herdrThumbs = inputs.herdr-plugin-thumbs.packages.${system}.default;

  configToml = ''
    # Managed by home-manager (home-manager/programs/herdr.nix). Edit there.

    [terminal]
    # CWD for new panes/tabs/workspaces created without an explicit --cwd.
    # Default is "follow" (inherit the source pane). ~/Work is where every repo
    # lives (~/Work/{forge}/{org}/{repo}), so a bare new workspace starts there
    # instead of $HOME. This key lives under [terminal] — at the top level it
    # parses fine and is silently dropped (herdr <=0.7.4 did not even warn).
    new_cwd = "${workDirTilde}"

    [ui]
    # Agent sidebar ordering: "spaces" (grouped by space, the default) or
    # "priority" (a single attention queue — blocked/working float to the top).
    agent_panel_sort = "priority"

    [keys]
    # ctrl-a prefix to match the tmux muscle memory.
    prefix = "ctrl+a"

    # Pane navigation: keep herdr's prefix+h/j/k/l and add no-prefix direct
    # chords mirroring the tmux alt+vim bindings. ctrl+alt is the one modifier
    # family herdr documents as safe across terminals/OSes (and immune to the
    # macOS alt-key composing that breaks plain alt+ chords).
    focus_pane_left = ["prefix+h", "ctrl+alt+h"]
    focus_pane_down = ["prefix+j", "ctrl+alt+j"]
    focus_pane_up = ["prefix+k", "ctrl+alt+k"]
    focus_pane_right = ["prefix+l", "ctrl+alt+l"]

    # Every [[keys.command]] carries a `description`: the prefix+? keybind
    # overlay renders custom binds in its "custom" group, and any entry without
    # one falls back to the literal string "custom command" — which makes the
    # whole group useless. Keep descriptions short; the overlay is one line each.

    # lazygit in a temporary pane (closes when lazygit exits).
    [[keys.command]]
    key = "prefix+alt+g"
    type = "pane"
    command = "lazygit"
    description = "lazygit in a temporary pane"

    # tmux M-r: PR/MR review. Clone + worktree + open a herdr workspace laid out
    # with a terminal (left) and tuicr on the PR/MR (right), matching the old
    # tmux-mr-review popup. Bound to alt+r to match that muscle memory.
    [[keys.command]]
    key = "alt+r"
    type = "pane"
    command = "${herdrMrReview}/bin/herdr-mr-review"
    description = "review a PR/MR: clone + worktree + tuicr"

    # --- Fuzzy finders / workspace creators (ported from tmux popups) ---
    #
    # Bound to plain alt+ single chords to match the tmux M-<key> muscle memory
    # (M-d/M-m/M-s/M-p were all `bind -n`, no prefix). This relies on Ghostty's
    # `macos-option-as-alt = true` (see ghostty.nix) so Option sends a real Alt
    # modifier instead of macOS-composing (alt+d -> ∂). Valid because herdr runs
    # as the top-level multiplexer directly in Ghostty (no tmux layer between).

    # tmux M-d: sesh connect picker. Pick an open workspace (-> focus it) or a
    # zoxide/find dir (-> open it as a workspace).
    [[keys.command]]
    key = "alt+d"
    type = "pane"
    command = "${herdrLauncher}/bin/herdr-launcher"
    description = "workspace picker: open workspaces / zoxide / find"

    # tmux M-m: clone-creator. gh/glab/URL repo picker -> clone -> open workspace.
    [[keys.command]]
    key = "alt+m"
    type = "pane"
    command = "${herdrClone}/bin/herdr-clone"
    description = "clone a repo (gh/glab/URL) -> new workspace"

    # tmux M-s: new workspace with a prompted name.
    # (herdr's native new_workspace = prefix+shift+n creates an unnamed one.)
    [[keys.command]]
    key = "alt+s"
    type = "pane"
    command = "${herdrNewNamed}/bin/herdr-new-named"
    description = "new workspace with a prompted name"

    # tmux-thumbs: hint-label every URL / path / hash on the focused pane, then
    # copy (lowercase hint) or open (UPPERCASE hint). prefix+space matches the
    # tmux-thumbs default. This binds the plugin's `launch` action (keybindings
    # can only be shell/pane/plugin_action — there is no plugin_pane bind type),
    # which opens the overlay pane. The plugin is linked at activation below.
    [[keys.command]]
    key = "prefix+space"
    type = "plugin_action"
    command = "${herdrThumbs.pluginId}.launch"
    description = "thumbs: hint + copy/open matches"
  '';
in
{
  home.packages = [
    herdr
    herdrHandoff
  ];

  xdg.configFile."herdr/config.toml".text = configToml;

  # Link the herdr-thumbs plugin from its store path. herdr keeps its plugin
  # registry in ~/.config/herdr; linking is idempotent here (unlink-then-link)
  # so a rebuild always points at the current store path. Guarded on the herdr
  # binary existing so activation doesn't fail on a machine mid-install.
  home.activation.herdrThumbsPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x "${herdr}/bin/herdr" ]; then
      run ${herdr}/bin/herdr plugin unlink ${herdrThumbs.pluginId} >/dev/null 2>&1 || true
      run ${herdr}/bin/herdr plugin link ${herdrThumbs} >/dev/null 2>&1 || \
        warnEcho "herdr-thumbs: plugin link failed (is the herdr server running?)"
    fi
  '';
}
