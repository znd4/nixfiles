{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf mkOption mkEnableOption types;
  cfg = config.programs.tmux-mr-review;

  workDir = builtins.replaceStrings [ "~" ] [ "$HOME" ] cfg.workDirectory;

  script = pkgs.writeShellApplication {
    name = "tmux-mr-review";

    runtimeInputs = with pkgs; [
      glab
      gh
      git
      gum
      jq
      coreutils
      tmux
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

      # Open tmux session — include repo name for context
      repo_name=$(basename "$project_path")
      session_name="review/$repo_name/$worktree_name"
      session_name=$(echo "$session_name" | tr '.:]' '---')

      if ! tmux has-session -t "=$session_name" 2>/dev/null; then
        tmux new-session -d -s "$session_name" -c "$worktree_dir"
      fi
      tmux switch-client -t "=$session_name"
    '';
  };
in
{
  options.programs.tmux-mr-review = {
    enable = mkEnableOption "tmux MR/PR review popup";

    keybinding = mkOption {
      type = types.str;
      default = "m";
      description = "Tmux keybinding (after prefix) for the MR review popup.";
    };

    workDirectory = mkOption {
      type = types.str;
      default = "~/Work";
      description = "Root directory where repos are cloned (~/Work/<host>/<project>).";
    };
  };

  config = mkIf cfg.enable {
    programs.tmux.extraConfig = ''
      bind ${cfg.keybinding} display-popup -E -w 80% -h 50% "${script}/bin/tmux-mr-review"
    '';
  };
}
