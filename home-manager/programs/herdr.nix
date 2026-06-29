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
      pkgs.glab
      pkgs.gh
      pkgs.git
      pkgs.gum
      pkgs.jq
      pkgs.coreutils
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

      # Fetch source branch
      if [ "$forge" = "github" ]; then
        source_branch=$(gh pr view "$pr_number" --repo "$project_path" --json headRefName -q '.headRefName')
      else
        source_branch=$(glab mr view "$pr_number" --repo "$project_path" --output json | jq -r '.source_branch')
      fi

      if [ -z "$source_branch" ] || [ "$source_branch" = "null" ]; then
        echo "Error: could not fetch source branch" >&2
        exit 1
      fi

      # Clone repo if needed
      repo_dir="$work_dir/$host/$project_path"
      if [ ! -d "$repo_dir" ]; then
        echo "Cloning $project_path..."
        mkdir -p "$(dirname "$repo_dir")"
        git clone "git@$host:$project_path.git" "$repo_dir"
      fi

      # Fetch the branch
      git -C "$repo_dir" fetch origin "$source_branch"

      # Create worktree
      worktree_name=$(echo "$source_branch" | tr '/' '-')
      worktree_dir="$repo_dir/.zn-work/$worktree_name"

      if [ ! -d "$worktree_dir" ]; then
        mkdir -p "$repo_dir/.zn-work"
        git -C "$repo_dir" worktree add "$worktree_dir" "origin/$source_branch" --detach
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
