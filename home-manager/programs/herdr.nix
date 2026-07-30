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

  workDir = "$HOME/Work";

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

  # Session/directory picker, ported from the tmux `M-d` sesh-connect popup. In
  # tmux that fzf drove `sesh connect` (all/tmux/zoxide/find/delete tabs). In
  # herdr the unit is a workspace, not a tmux session, so this picks a directory
  # (zoxide history, or a shallow `fd` of ~/Work) and opens it as a workspace.
  # ctrl-x = zoxide, ctrl-f = find; matches the tmux popup's header chords.
  herdrSeshPick = pkgs.writeShellApplication {
    name = "herdr-sesh-pick";
    runtimeInputs = [
      pkgs.fzf
      pkgs.fd
      pkgs.coreutils
      herdr
    ];
    text = ''
      dir=$(sesh list -z 2>/dev/null | fzf \
          --no-sort --border --border-label ' herdr workspace ' --prompt '📁  ' \
          --header '  ^x zoxide  ^f find (~/Work)' \
          --bind 'tab:down,btab:up' \
          --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z)' \
          --bind "ctrl-f:change-prompt(🔎  )+reload(fd -H -d 4 -t d -E .Trash -E .git . ${workDir})" \
        ) || exit 0
      [ -z "$dir" ] && exit 0
      # Expand a leading ~ (sesh list -z emits ~-relative paths).
      dir="''${dir/#\~/$HOME}"
      herdr workspace create --cwd "$dir" --label "$(basename "$dir")" --focus
    '';
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
      herdr workspace create --cwd "$HOME" --label "$name" --focus
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

    # lazygit in a temporary pane (closes when lazygit exits).
    [[keys.command]]
    key = "prefix+alt+g"
    type = "pane"
    command = "lazygit"

    # tmux M-r: PR/MR review. Clone + worktree + open a herdr workspace laid out
    # with a terminal (left) and tuicr on the PR/MR (right), matching the old
    # tmux-mr-review popup. Bound to alt+r to match that muscle memory.
    [[keys.command]]
    key = "alt+r"
    type = "pane"
    command = "${herdrMrReview}/bin/herdr-mr-review"

    # --- Fuzzy finders / workspace creators (ported from tmux popups) ---
    #
    # Bound to plain alt+ single chords to match the tmux M-<key> muscle memory
    # (M-d/M-m/M-s/M-p were all `bind -n`, no prefix). This relies on Ghostty's
    # `macos-option-as-alt = true` (see ghostty.nix) so Option sends a real Alt
    # modifier instead of macOS-composing (alt+d -> ∂). Valid because herdr runs
    # as the top-level multiplexer directly in Ghostty (no tmux layer between).

    # tmux M-d: sesh connect picker. Pick a zoxide/find dir -> open as workspace.
    [[keys.command]]
    key = "alt+d"
    type = "pane"
    command = "${herdrSeshPick}/bin/herdr-sesh-pick"

    # tmux M-m: clone-creator. gh/glab/URL repo picker -> clone -> open workspace.
    [[keys.command]]
    key = "alt+m"
    type = "pane"
    command = "${herdrClone}/bin/herdr-clone"

    # tmux M-s: new workspace with a prompted name.
    # (herdr's native new_workspace = prefix+shift+n creates an unnamed one.)
    [[keys.command]]
    key = "alt+s"
    type = "pane"
    command = "${herdrNewNamed}/bin/herdr-new-named"

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
  home.packages = [ herdr ];

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
