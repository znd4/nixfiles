{
  inputs,
  system,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.programs.znd4-television;

  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
  # tv from its own pin rather than `nixpkgs-unstable`, which still has 0.13.5.
  # See flake.nix for why (0.13.5 shows a stale preview once a query narrows
  # the results). herdr.nix reads tv from this same input so the launcher and
  # this config can never drift onto different versions.
  televisionPkgs = inputs.nixpkgs-television.legacyPackages.${system};

  # each line: <iid> <project-path> @<author> <title...> <web-url>.
  # the URL sits last so `{split: :-1}` (output template) extracts it;
  # `{0}` and `{1}` give the preview command the iid and project path.
  mrLines = ''jq -r '.[] | "\(.iid) \(.references.full | split("!")[0]) @\(.author.username) \(.title) \(.web_url)"' '';

  # instance-wide MR search. `--hostname` lets it work outside a git repo,
  # where glab has no remote to infer the host from.
  glabMrs =
    host: query:
    ''glab api --hostname ${host} "merge_requests?state=opened&order_by=updated_at&per_page=100&${query}" 2>/dev/null | ''
    + mrLines;

  # ctrl-s cycles these in order, so the first entry is what `tv mrs` opens
  # with. That first entry is every open MR in the repo of the current directory
  # (mine or not) — the repo you are sitting in is almost always the one you
  # want, and it needs no host because glab infers it from the remote. The up to
  # three instance-wide queries per configured host follow. With no hosts
  # configured the repo-local source is the only one, which is still a usable
  # channel.
  mrSources = [
    ("glab mr list --output json --per-page 100 2>/dev/null | " + mrLines)
  ]
  ++ lib.concatMap (
    host:
    [ (glabMrs host "scope=created_by_me") ]
    # no `scope=review_requested_by_me` exists, so this one needs the
    # username spelled out; skip it when none is configured rather than
    # spending a `glab api user` round trip on every launch.
    ++ lib.optional (cfg.gitlab.username != null) (
      glabMrs host "scope=all&reviewer_username=${cfg.gitlab.username}"
    )
    ++ [ (glabMrs host "scope=assigned_to_me") ]
  ) cfg.gitlab.hosts;
in
{
  options.programs.znd4-television.gitlab = {
    hosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        GitLab hostnames the `mrs` channel searches instance-wide. Each host
        contributes its own set of sources, cycled with ctrl-s in list order.
      '';
      example = [ "gitlab.com" ];
    };

    username = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Your GitLab username, used for the "review requested of me" source of
        the `mrs` channel. That source is dropped when this is null.
      '';
    };
  };

  config = {
    programs.television = {
      enable = true;
      package = televisionPkgs.television;
      channels = {
        # Upstream builtins (tv update-channels can't fetch due to corporate TLS)
        files = {
          metadata = {
            name = "files";
            description = "A channel to select files and directories";
            requirements = [
              "fd"
              "bat"
            ];
          };
          # hidden-by-default: the first command is what ctrl-t opens with.
          # ctrl-s cycles to the second (no dotfiles).
          source.command = [
            "fd -t f -H -E .git"
            "fd -t f"
          ];
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
          source.command = [
            "fd -t d -H -E .git"
            "fd -t d"
          ];
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
            requirements = [
              "rg"
              "bat"
            ];
          };
          source = {
            command = [
              "rg . --no-heading --line-number --hidden -g '!.git' --colors 'match:fg:white' --colors 'path:fg:blue' --color=always"
              "rg . --no-heading --line-number --colors 'match:fg:white' --colors 'path:fg:blue' --color=always"
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
          # enter prints "filepath:line" to stdout (the `output` template) so the
          # channel composes with shell command substitution, e.g. `vi (tv text)`.
          # The in-tv editor action stays available on ctrl-e.
          keybindings.ctrl-e = "actions:edit";
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
            requirements = [
              "fd"
              "git"
            ];
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
            requirements = [
              "glab"
              "jq"
            ];
          };
          source.command = ''glab api "projects/$(echo "$@" | sed 's|/|%2F|g')/pipeline_schedules" 2>/dev/null | jq -r '.[] | "\(.id)\t\(.description)\t\(.cron)\tactive=\(.active)\tnext=\(.next_run_at)"' '';
          preview.command = ''glab api "projects/$(echo "$@" | sed 's|/|%2F|g')/pipeline_schedules/{0}" 2>/dev/null | jq -C '{id, description, cron, cron_timezone, ref, active, next_run_at, last_pipeline, owner: .owner.username, variables: [.variables[]? | "\(.key)=\(.value)"]}'  '';
        };
        mrs = {
          metadata = {
            name = "mrs";
            description = "A channel to select from GitLab merge requests; prints the MR URL";
            requirements = [
              "glab"
              "jq"
            ];
          };
          source = {
            command = mrSources;
            # enter emits the URL (last field); hide it from the display.
            # `..-1` is end-exclusive: every field except the last.
            display = "{split: :..-1}";
            # just the URL on stdout — composes as `glab mr view $(tv mrs)`.
            output = "{split: :-1}";
          };
          preview.command = "glab mr view --repo '{1}' '{0}' 2>&1";
          ui.preview_panel = {
            size = 60;
            header = "{1}!{0}";
          };
          keybindings.alt-o = "actions:browse";
          actions.browse = {
            description = "Open the merge request in a browser";
            command = "glab mr view --repo '{1}' '{0}' --web";
            mode = "execute";
          };
        };
        git-worktrees = {
          metadata = {
            name = "git-worktrees";
            description = "A channel to select from git worktrees of the current repo";
            requirements = [ "git" ];
          };
          # `git worktree list --porcelain` emits a `worktree <path>` line per
          # tree; pull out just the paths. Errors (not in a repo) yield an empty
          # list.
          source = {
            command = "git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10)}'";
            display = "{split:/:-1}";
          };
          preview.command = "cd '{}'; git -c color.ui=always log -n 200 --pretty=medium --graph";
          # enter is left as the default (print the selected path to stdout) so
          # the channel composes with command substitution, e.g.
          # `cd (tv git-worktrees)`. The `tw` fish function below relies on this
          # to cd the *current* shell. cd-into-a-subshell and edit stay available
          # on their own keys.
          keybindings = {
            # ctrl-o is the global toggle_preview; use alt-o for the subshell
            # action.
            alt-o = "actions:cd";
            ctrl-e = "actions:edit";
          };
          actions.cd = {
            description = "Open a new shell in the selected worktree";
            command = "cd '{}' && $SHELL";
            mode = "execute";
          };
          actions.edit = {
            description = "Open the worktree in editor";
            command = "$EDITOR '{}'";
            mode = "execute";
          };
        };
      };
    };

    programs.nix-search-tv = {
      enable = true;
      package = unstablePkgs.nix-search-tv;
    };

    # `tw`: pick a worktree and cd the *current* fish shell into it. A child
    # process can't change the parent's cwd, so this shell wrapper is required —
    # `tv git-worktrees` prints the chosen path on enter, and we cd to it. Bound
    # to Alt-w below.
    programs.fish.functions.tw = ''
      set -l dir (tv git-worktrees)
      if test -n "$dir"
          cd $dir
      end
    '';

    # Bind Alt-w to `tw` in both insert and default (normal) vi modes.
    #
    # fish.nix calls `fish_vi_key_bindings` directly in interactiveShellInit.
    # That call resets all bindings and bypasses fish's `fish_user_key_bindings`
    # hook (the hook only fires when the `fish_key_bindings` variable changes,
    # not on a direct call). A one-shot `fish_prompt` handler works around this:
    # it runs after all init completes, so the binding survives regardless of
    # module ordering.
    programs.fish.interactiveShellInit = ''
      function __tw_bind --on-event fish_prompt
          functions -e __tw_bind
          # `tw` changes the cwd, but a binding that changes directory doesn't
          # repaint the prompt — starship keeps showing the old path until the
          # next prompt. Force an in-place repaint (same as fzf.fish's dir widget).
          bind -M insert \ew 'tw; commandline -f repaint'
          bind -M default \ew 'tw; commandline -f repaint'
      end
    '';
  };
}
