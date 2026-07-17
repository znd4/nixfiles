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
  # for a PR/MR URL, resolve the source branch, clone the repo if needed, add a
  # detached worktree, then open it as a herdr workspace (instead of a tmux
  # session). Bound below as a herdr custom-command pane.
  herdrMrReview = pkgs.writeShellApplication {
    name = "herdr-mr-review";
    runtimeInputs = [
      pkgs.git
      pkgs.gum
      pkgs.coreutils
      pkgs.gh
      pkgs.glab
      pkgs.jq
      herdr
    ];
    text = ''
      url=$(gum input --placeholder "PR/MR URL (e.g. https://github.com/org/repo/pull/123)")
      [ -z "$url" ] && exit 0

      work_dir="${workDir}"

      # Detect forge type and parse URL
      if [[ "$url" =~ ^https://github\.com/([^/]+/[^/]+)/pull/([0-9]+)$ ]]; then
        forge="github"
        host="github.com"
        project_path="''${BASH_REMATCH[1]}"
        pr_number="''${BASH_REMATCH[2]}"
      elif [[ "$url" =~ ^https://([^/]+)/(.+)/-/merge_requests/([0-9]+)$ ]]; then
        forge="gitlab"
        host="''${BASH_REMATCH[1]}"
        project_path="''${BASH_REMATCH[2]}"
        pr_number="''${BASH_REMATCH[3]}"
      else
        echo "Error: URL must be a GitHub PR or GitLab MR link" >&2
        exit 1
      fi

      # Forge head ref (by number) is the robust fallback: it resolves for fork
      # PRs and for merged PRs/MRs whose branch was deleted.
      if [ "$forge" = "github" ]; then
        head_ref="pull/$pr_number/head"
        review_branch="pr-$pr_number"
      else
        head_ref="merge-requests/$pr_number/head"
        review_branch="mr-$pr_number"
      fi

      # Clone repo if needed
      repo_dir="$work_dir/$host/$project_path"
      if [ ! -d "$repo_dir" ]; then
        echo "Cloning $project_path..."
        mkdir -p "$(dirname "$repo_dir")"
        git clone "git@$host:$project_path.git" "$repo_dir"
      fi

      # Resolve the source remote + branch via the forge API so we can check out
      # a real local branch (pr-N / mr-N) tracking the contributor's source —
      # rather than a detached head. Cross-repo (fork) sources are added as a
      # remote named after the fork owner. Falls back to the forge head ref when
      # the API is unavailable.
      source_remote="origin"
      source_branch=""
      fork_url=""
      if [ "$forge" = "github" ]; then
        if mr_json=$(gh pr view "$pr_number" --repo "$project_path" \
              --json headRefName,headRepositoryOwner,headRepository,isCrossRepository 2>/dev/null); then
          source_branch=$(printf '%s' "$mr_json" | jq -r '.headRefName')
          if [ "$(printf '%s' "$mr_json" | jq -r '.isCrossRepository')" = "true" ]; then
            fork_owner=$(printf '%s' "$mr_json" | jq -r '.headRepositoryOwner.login')
            fork_repo=$(printf '%s' "$mr_json" | jq -r '.headRepository.name')
            source_remote="$fork_owner"
            fork_url="git@$host:$fork_owner/$fork_repo.git"
          fi
        fi
      else
        if mr_json=$(glab mr view "$pr_number" --repo "$project_path" --output json 2>/dev/null); then
          source_branch=$(printf '%s' "$mr_json" | jq -r '.source_branch')
          src_pid=$(printf '%s' "$mr_json" | jq -r '.source_project_id')
          tgt_pid=$(printf '%s' "$mr_json" | jq -r '.target_project_id')
          if [ -n "$src_pid" ] && [ "$src_pid" != "$tgt_pid" ] && [ "$src_pid" != "null" ]; then
            if proj_json=$(glab api "projects/$src_pid" 2>/dev/null); then
              source_remote=$(printf '%s' "$proj_json" | jq -r '.path_with_namespace' | tr '/' '-')
              fork_url=$(printf '%s' "$proj_json" | jq -r '.ssh_url_to_repo')
            fi
          fi
        fi
      fi

      if [ -n "$source_branch" ] && [ "$source_branch" != "null" ]; then
        if [ "$source_remote" != "origin" ] && [ -n "$fork_url" ]; then
          if ! git -C "$repo_dir" remote get-url "$source_remote" >/dev/null 2>&1; then
            git -C "$repo_dir" remote add "$source_remote" "$fork_url"
          fi
        fi
        git -C "$repo_dir" fetch -q "$source_remote" \
            "+refs/heads/$source_branch:refs/remotes/$source_remote/$source_branch" \
          || { echo "Error: could not fetch $source_branch from $source_remote" >&2; exit 1; }
        start_point="$source_remote/$source_branch"
      else
        # API unavailable — fall back to the forge head ref.
        git -C "$repo_dir" fetch -q origin "+$head_ref:refs/review/$forge-$pr_number" \
          || { echo "Error: could not fetch $head_ref" >&2; exit 1; }
        start_point="refs/review/$forge-$pr_number"
      fi

      # Create/refresh the worktree on the review branch.
      worktree_name="$forge-$pr_number"
      worktree_dir="$repo_dir/.zn-work/$worktree_name"
      if [ -d "$worktree_dir" ]; then
        git -C "$worktree_dir" checkout -q -B "$review_branch" "$start_point" 2>/dev/null || true
      else
        mkdir -p "$repo_dir/.zn-work"
        git -C "$repo_dir" worktree add -q -B "$review_branch" "$worktree_dir" "$start_point" \
          || { echo "Error: could not create worktree at $worktree_dir" >&2; exit 1; }
      fi

      # Open as a herdr workspace (rather than a tmux session)
      repo_name=$(basename "$project_path")
      label="review/$repo_name/$worktree_name"
      herdr workspace create --cwd "$worktree_dir" --label "$label" --focus
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

  configToml = ''
    # Managed by home-manager (home-manager/programs/herdr.nix). Edit there.

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

    # PR/MR review workflow (clone + worktree + open herdr workspace).
    [[keys.command]]
    key = "prefix+m"
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

    # tmux M-p: open the current repo's pull request in the browser.
    # _pull-request-open runs `git rev-parse` and errors outside a repo. A
    # command pane does NOT start in the focused repo automatically, so cd into
    # $HERDR_ACTIVE_PANE_CWD first — the focused pane's cwd, which herdr injects
    # into custom commands (per herdr.dev/docs/configuration). `|| read` keeps
    # the pane open on error so the message stays readable.
    [[keys.command]]
    key = "alt+p"
    type = "pane"
    command = "cd \"''${HERDR_ACTIVE_PANE_CWD:-$PWD}\" && _pull-request-open || { echo; read -rp 'Press enter to close…'; }"
  '';
in
{
  home.packages = [ herdr ];

  xdg.configFile."herdr/config.toml".text = configToml;
}
