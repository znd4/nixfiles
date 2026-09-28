# Home-manager module for workmux (https://github.com/raine/workmux), which
# pairs git worktrees with tmux windows. Upstream ships a package but no
# module. This file uses no inputs from this flake, so other flakes can import
# it as homeModules.workmux. They must set `package` themselves.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    literalExpression
    mapAttrsToList
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    types
    ;
  cfg = config.programs.workmux;
  bindings = lib.filterAttrs (_: command: command != null) cfg.tmuxIntegration.bindings;
  yaml = pkgs.formats.yaml { };

  # The hooks from upstream's .claude-plugin/plugin.json. Each command runs
  # `workmux` from PATH, as upstream does, so a package update does not leave
  # old store paths in settings.json.
  claudeHooks = [
    {
      event = "SessionStart";
      matcher = "startup|resume|clear|fork";
      command = "workmux register-agent";
    }
    {
      event = "UserPromptSubmit";
      command = "workmux set-window-status working";
    }
    {
      event = "Notification";
      matcher = "permission_prompt|elicitation_dialog";
      command = "workmux set-window-status waiting";
    }
    {
      event = "PostToolUse";
      command = "workmux set-window-status working";
    }
    {
      event = "Stop";
      command = "workmux set-window-status done";
    }
  ];

  # Adds each hook to settings.json unless a hook with the same command is
  # already there. Hooks that the user or other tools wrote are kept.
  mergeClaudeHooks = pkgs.writeText "workmux-claude-hooks.jq" ''
    reduce $hooks[] as $h (.;
      if any(.hooks[$h.event][]?.hooks[]?; .command == $h.command) then .
      else .hooks[$h.event] += [
        ({ hooks: [{ type: "command", command: $h.command }] }
          + (if $h.matcher then { matcher: $h.matcher } else {} end))
      ]
      end)
  '';
in
{
  options.programs.workmux = {
    enable = mkEnableOption "workmux, git worktrees paired with tmux windows";

    package = mkOption {
      type = types.package;
      example = literalExpression "inputs.workmux.packages.\${pkgs.system}.default";
      description = ''
        The workmux package. nixpkgs does not have it. Use the upstream flake
        (github:raine/workmux) or pkgs.llm-agents.workmux from
        https://github.com/numtide/llm-agents.nix. Both install the shell
        completions.
      '';
    };

    settings = mkOption {
      inherit (yaml) type;
      default = { };
      example = literalExpression ''
        {
          nerdfont = true;
          worktree_dir = ".worktrees";
          merge_strategy = "rebase";
          panes = [
            { command = "<agent>"; focus = true; }
            { split = "horizontal"; }
          ];
        }
      '';
      description = ''
        Global configuration, written to $XDG_CONFIG_HOME/workmux/config.yaml.
        Run `workmux config reference` for all keys. The file is read-only.
        Set `nerdfont`: if it is not set, workmux asks on the first run and
        then cannot write the answer to this file.
      '';
    };

    tmuxIntegration = {
      enable = mkOption {
        type = types.bool;
        default = config.programs.tmux.enable;
        defaultText = literalExpression "config.programs.tmux.enable";
        description = "Add the workmux key bindings to programs.tmux.extraConfig.";
      };

      bindings = mkOption {
        type = types.attrsOf (types.nullOr types.str);
        default = { };
        example = literalExpression ''
          {
            # upstream's recommended bindings (all after the prefix)
            "C-s" = "display-popup -h 30 -w 100 -E \"workmux dashboard\"";
            "C-w" = "display-popup -h 30 -w 100 -E \"workmux dashboard --tab worktrees\"";
            "C-t" = "run-shell \"workmux sidebar\"";
            "L" = "run-shell \"workmux last-done\"";
            "Tab" = "run-shell \"workmux last-agent\"";
          }
        '';
        description = ''
          tmux key bindings, as key to tmux command. Each entry becomes
          `bind-key <key> <command>`, so you press the key after the prefix.
          To bind without the prefix, put the flag in the key, for example
          `"-n M-w"`. Set a key to null to remove it, for example to unbind a
          key that another module sets. The default is empty. Key choice is
          personal, and upstream's recommended keys can collide with tmux
          plugins (for example, tmux-resurrect uses prefix C-s).
        '';
      };
    };

    shellAlias = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "wm";
      description = ''
        A short name for `workmux`. Fish gets it as an abbreviation, which
        expands to `workmux` when you type it. Bash and zsh get it as an
        alias. The default, null, adds nothing.
      '';
    };

    enableBashIntegration = lib.hm.shell.mkBashIntegrationOption { inherit config; };
    enableFishIntegration = lib.hm.shell.mkFishIntegrationOption { inherit config; };
    enableZshIntegration = lib.hm.shell.mkZshIntegrationOption { inherit config; };

    claudeCode.hooks.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Merge the workmux status hooks into ~/.claude/settings.json on each
        home-manager activation. The hooks show the agent state (working,
        waiting, done) in the tmux window list. This is the same as
        `workmux setup --hooks`, but it runs on every switch and keeps all
        other settings. If you disable this option, the hooks that it added
        stay in the file.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      home.packages = [ cfg.package ];

      # `workmux update` replaces its own binary, and the update check tells
      # you to run it. Neither works, because the Nix store is read-only.
      programs.workmux.settings.auto_update_check = mkDefault false;

      warnings = optional (!(cfg.settings ? nerdfont)) ''
        programs.workmux.settings.nerdfont is not set. workmux asks on the
        first run and then cannot save the answer, because
        ~/.config/workmux/config.yaml is read-only.
      '';

      xdg.configFile."workmux/config.yaml".source = yaml.generate "workmux-config.yaml" cfg.settings;
    }

    (mkIf (cfg.tmuxIntegration.enable && bindings != { }) {
      programs.tmux.extraConfig = concatStringsSep "\n" (
        mapAttrsToList (key: command: "bind-key ${key} ${command}") bindings
      );
    })

    (mkIf (cfg.shellAlias != null) {
      programs.bash.shellAliases = mkIf cfg.enableBashIntegration { ${cfg.shellAlias} = "workmux"; };
      programs.fish.shellAbbrs = mkIf cfg.enableFishIntegration { ${cfg.shellAlias} = "workmux"; };
      programs.zsh.shellAliases = mkIf cfg.enableZshIntegration { ${cfg.shellAlias} = "workmux"; };
    })

    (mkIf cfg.claudeCode.hooks.enable {
      home.activation.workmuxClaudeHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings="${config.home.homeDirectory}/.claude/settings.json"
        if [ ! -e "$settings" ]; then
          run mkdir -p "$(dirname "$settings")"
          run sh -c 'echo "{}" > "$1"' _ "$settings"
        fi
        tmp="$(mktemp)"
        if ${pkgs.jq}/bin/jq --argjson hooks ${lib.escapeShellArg (builtins.toJSON claudeHooks)} \
          -f ${mergeClaudeHooks} "$settings" > "$tmp"; then
          if ! cmp -s "$tmp" "$settings"; then
            run cp "$tmp" "$settings"
          fi
        else
          warnEcho "workmux: could not merge the Claude Code hooks into $settings"
        fi
        rm -f "$tmp"
      '';
    })
  ]);
}
