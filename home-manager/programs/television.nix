{ inputs, system, ... }:
let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
in
{
  programs.television = {
    enable = true;
    package = unstablePkgs.television;
    channels = {
      # Upstream builtins (tv update-channels can't fetch due to corporate TLS)
      files = {
        metadata = {
          name = "files";
          description = "A channel to select files and directories";
          requirements = [ "fd" "bat" ];
        };
        source.command = [ "fd -t f" "fd -t f -H" ];
        preview = {
          command = "bat -n --color=always '{}'";
          env.BAT_THEME = "ansi";
        };
        keybindings = {
          shortcut = "f1";
          f12 = "actions:edit";
          ctrl-up = "actions:goto_parent_dir";
        };
        actions.edit = {
          description = "Opens the selected entries with the default editor";
          command = "$EDITOR '{}'";
          mode = "execute";
        };
        actions.goto_parent_dir = {
          description = "Re-opens tv in the parent directory";
          command = "tv files ..";
          mode = "execute";
        };
      };
      dirs = {
        metadata = {
          name = "dirs";
          description = "A channel to select from directories";
          requirements = [ "fd" ];
        };
        source.command = [ "fd -t d" "fd -t d --hidden" ];
        preview.command = "ls -la --color=always '{}'";
        keybindings.shortcut = "f2";
        actions.cd = {
          description = "Open a shell in the selected directory";
          command = "cd '{}' && $SHELL";
          mode = "execute";
        };
        actions.goto_parent_dir = {
          description = "Re-opens tv in the parent directory";
          command = "tv dirs ..";
          mode = "execute";
        };
      };
      env = {
        metadata.name = "env";
        metadata.description = "A channel to select from environment variables";
        source = {
          command = "printenv";
          output = "{split:=:1..}";
        };
        preview.command = "echo '{split:=:1..}'";
        ui = {
          layout = "portrait";
          preview_panel = {
            size = 20;
            header = "{split:=:0}";
          };
        };
        keybindings.shortcut = "f3";
        actions.name = {
          description = "Output the variable name instead of the value";
          command = "echo '{split:=:0}'";
          mode = "execute";
        };
      };
      text = {
        metadata = {
          name = "text";
          description = "A channel to find and select text from files";
          requirements = [ "rg" "bat" ];
        };
        source = {
          command = [
            "rg . --no-heading --line-number --colors 'match:fg:white' --colors 'path:fg:blue' --color=always"
            "rg . --no-heading --line-number --hidden -g '!.git' --colors 'match:fg:white' --colors 'path:fg:blue' --color=always"
          ];
          ansi = true;
          output = "{strip_ansi|split:\\::..2}";
        };
        preview = {
          command = "bat -n --color=always '{strip_ansi|split:\\::0}'";
          env.BAT_THEME = "ansi";
          offset = "{strip_ansi|split:\\::1}";
        };
        ui.preview_panel.header = "{strip_ansi|split:\\::..2}";
        keybindings.enter = "actions:edit";
        actions.edit = {
          description = "Open file in editor at line";
          command = "$EDITOR '+{strip_ansi|split:\\::1}' '{strip_ansi|split:\\::0}'";
          mode = "execute";
        };
      };
      alias = {
        metadata = {
          name = "alias";
          description = "A channel to select from shell aliases";
        };
        source = {
          command = "$SHELL -ic 'alias'";
          output = "{split:=:0}";
        };
        preview.command = "$SHELL -ic 'alias' | grep -E '^(alias )?{split:=:0}='";
        ui.preview_panel.size = 30;
      };
      git-repos = {
        metadata = {
          name = "git-repos";
          description = "A channel to select from git repositories on your local machine";
          requirements = [ "fd" "git" ];
        };
        source = {
          command = "fd -g .git -HL -t d -d 10 --prune ~ -E 'Library' -E 'Application Support' --exec dirname '{}'";
          display = "{split:/:-1}";
        };
        preview.command = "cd '{}'; git log -n 200 --pretty=medium --all --graph --color";
        keybindings = {
          enter = "actions:cd";
          ctrl-e = "actions:edit";
        };
        actions.cd = {
          description = "Open a new shell in the selected repository";
          command = "cd '{}' && $SHELL";
          mode = "execute";
        };
        actions.edit = {
          description = "Open the repository in editor";
          command = "$EDITOR '{}'";
          mode = "execute";
        };
      };

      # Custom channels
      git-diff = {
        metadata.name = "git-diff";
        source.command = "git diff --name-only";
        preview.command = "git diff --color=always {0}";
      };
      git-reflog = {
        metadata.name = "git-reflog";
        source.command = "git reflog";
        preview.command = "git show -p --stat --pretty=fuller --color=always {0}";
      };
      git-log = {
        metadata.name = "git-log";
        source.command = ''git log --oneline --date=short --pretty="format:%h %s %an %cd" "$@"'';
        preview.command = "git show -p --stat --pretty=fuller --color=always {0}";
      };
      git-branch = {
        metadata.name = "git-branch";
        source.command = ''git --no-pager branch --all --format="%(refname:short)"'';
        preview.command = "git show -p --stat --pretty=fuller --color=always {0}";
      };
      docker-images = {
        metadata.name = "docker-images";
        source.command = ''docker image list --format "{{.ID}}"'';
        preview.command = "docker image inspect {0} | jq -C";
      };
      s3-buckets = {
        metadata.name = "s3-buckets";
        source.command = ''aws s3 ls | cut -d " " -f 3'';
        preview.command = "aws s3 ls s3://{0}";
      };
      my-dotfiles = {
        metadata.name = "my-dotfiles";
        source.command = "fd -t f . $HOME/.config";
        preview.command = ":files:";
      };
      fish-history = {
        metadata.name = "fish-history";
        source.command = "fish -c 'history'";
      };
      glab-cron = {
        metadata = {
          name = "glab-cron";
          description = "GitLab CI pipeline schedules for a given project";
          requirements = [ "glab" "jq" ];
        };
        source.command = ''glab api "projects/$(echo "$@" | sed 's|/|%2F|g')/pipeline_schedules" 2>/dev/null | jq -r '.[] | "\(.id)\t\(.description)\t\(.cron)\tactive=\(.active)\tnext=\(.next_run_at)"' '';
        preview.command = ''glab api "projects/$(echo "$@" | sed 's|/|%2F|g')/pipeline_schedules/{0}" 2>/dev/null | jq -C '{id, description, cron, cron_timezone, ref, active, next_run_at, last_pipeline, owner: .owner.username, variables: [.variables[]? | "\(.key)=\(.value)"]}'  '';
      };
    };
  };

  programs.nix-search-tv = {
    enable = true;
    package = unstablePkgs.nix-search-tv;
  };
}
