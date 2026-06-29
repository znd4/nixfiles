{
  inputs,
  system,
  pkgs,
  ...
}:
let
  herdr = inputs.herdr.packages.${system}.default;

  workDir = "$HOME/Work";

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
  '';
in
{
  home.packages = [ herdr ];

  xdg.configFile."herdr/config.toml".text = configToml;
}
