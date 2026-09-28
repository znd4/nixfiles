{
  pkgs,
  lib,
  config,
  inputs,
  system,
  seshClConfig,
  ...
}:
let
  cfg = config.programs.tmux-new-session;

  # The scripts look up fzf and jq on PATH. The tmux server PATH can lack
  # them, so postInstall adds the Nix store paths to the start of PATH in
  # each script.
  claude-hatch = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "claude-hatch";
    version = "1.5.0";
    src = inputs.tmux-claude-hatch;
    postInstall = ''
      for f in $target/scripts/*.sh; do
        sed -i '1a export PATH=${
          lib.makeBinPath [
            pkgs.fzf
            pkgs.jq
          ]
        }:$PATH' "$f"
      done
    '';
  };
in
{
  options.programs.tmux-new-session = {
    enable = lib.mkEnableOption "tmux new session popup (Alt+s)";
    keybinding = lib.mkOption {
      type = lib.types.str;
      default = "M-s";
      description = "Tmux keybinding for the new session popup.";
    };
    defaultDirectory = lib.mkOption {
      type = lib.types.str;
      default = "~";
      description = "Default working directory for new tmux sessions.";
    };
  };

  config = {
    programs.fzf.tmux.enableShellIntegration = true;
    programs.tmux = {
      disableConfirmationPrompt = true;
      enable = true;
      historyLimit = 10000;
      keyMode = "vi";
      mouse = true;
      shell = "${pkgs.fish}/bin/fish";
      terminal = "tmux-256color";
      tmuxinator.enable = true;
      # TODO: try out tmuxp
      # tmuxp.enable = true;
      extraConfig = ''
        set -g default-command ${pkgs.fish}/bin/fish
        bind -n M-d run-shell "sesh connect $(
          sesh list -tzs | fzf-tmux -p 55%,60% \
          		--no-sort --border-label ' sesh ' --prompt '⚡  ' \
          		--header '  ^a all ^t tmux ^x zoxide ^f find ^d delete' \
          		--bind 'tab:down,btab:up' \
          		--bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list)' \
          		--bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t)' \
          		--bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z)' \
          		--bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
          		--bind 'ctrl-d:execute-silent(tmux kill-session -t {})+reload(sesh list -tzs)'
        ) || true"

        bind -n M-m display-popup -E "_sesh-cl-fuzzy \
          --gitlab-hosts '[${lib.strings.concatStringsSep " " seshClConfig.gitlabHosts}]' \
          --github-orgs '[${lib.strings.concatStringsSep " " seshClConfig.githubOrgs}]' \
          --parent-directory '[${lib.strings.concatStringsSep " " seshClConfig.parentDirectories}]'
        "

        bind -n M-M display-popup "_sesh-cl-fuzzy \
          --gitlab-hosts '[${lib.strings.concatStringsSep " " seshClConfig.gitlabHosts}]' \
          --github-orgs '[${lib.strings.concatStringsSep " " seshClConfig.githubOrgs}]' \
          --parent-directory '[${lib.strings.concatStringsSep " " seshClConfig.parentDirectories}]'
        "


        # use alt+vim movement between panes
        bind -n M-h select-pane -L
        bind -n M-j select-pane -D
        bind -n M-k select-pane -U
        bind -n M-l select-pane -R

        # open pull request in browser
        bind -n M-p run-shell "_pull-request-open"

        # alt+shift+g: lazygit in a popup, in the focused pane's directory.
        # This replaces herdr's alt+shift+g (herdr-agent-lazygit). tmux needs
        # no script: #{pane_current_path} is the directory of the pane's
        # foreground process. In a Claude pane, that is Claude's working directory.
        bind -n M-G display-popup -E -w 85% -h 80% -d "#{pane_current_path}" lazygit
        # prefix+alt+g: lazygit in a temporary split. It closes when lazygit exits.
        bind M-g split-window -c "#{pane_current_path}" lazygit

        set -s set-clipboard off
        if-shell "[ -z '$WAYLAND_DISPLAY' ]" \
            "set -s copy-command 'cb copy'" \
            "set -s copy-command 'wl-copy'" \

        set -g @thumbs-command 'echo -n {} | `tmux show-options -vs copy-command` && tmux display-message "Copied {}"'

        # vi mode
        bind P paste-buffer
        bind-key -T copy-mode-vi v send-keys -X begin-selection
        bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel
        set-window-option -g mode-keys vi

        bind C-a send-prefix


        unbind r
        bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded tmux configuration"

        # Turn the mouse on, but without copy mode dragging
        unbind -n MouseDrag1Pane
        unbind -Tcopy-mode MouseDrag1Pane

        # allow passthrough (e.g. for iterm image protocol)
        set-option -g allow-passthrough on

        bind @ break-pane -d
      ''
      + lib.optionalString cfg.enable ''

        # new session popup
        bind -n ${cfg.keybinding} display-popup -E '${pkgs.writeShellScript "tmux-new-session" ''
          name=$(${pkgs.gum}/bin/gum input --placeholder "session name")
          [ -z "$name" ] && exit 0
          dir="${cfg.defaultDirectory}"
          dir="''${dir/#\~/$HOME}"
          tmux new-session -d -s "$name" -c "$dir"
          tmux switch-client -t "$name"
        ''}'
      '';

      plugins = with pkgs.tmuxPlugins; [
        battery
        {
          plugin = catppuccin;
          extraConfig = ''
            set -g @catppuccin_flavor 'macchiato'
            set -g @catppuccin_window_status_style 'rounded'

            set -g status-right-length 100
            set -g status-left-length 100
            set -g status-left ""
            set -g status-right "#{E:@catppuccin_status_application}"
            set -agF status-right "#{E:@catppuccin_status_cpu}"
            set -ag status-right "#{E:@catppuccin_status_session}"
            set -ag status-right "#{E:@catppuccin_status_uptime}"
            set -agF status-right "#{E:@catppuccin_status_battery}"
          '';
        }
        pain-control
        sensible
        tmux-fzf
        # prefix (C-a) y: open Claude for this directory;
        # prefix u: select a running Claude session from a list
        claude-hatch
        {
          plugin = tmux-thumbs;
          extraConfig = ''
            set -g @thumbs-upcase-command '${if pkgs.stdenv.isDarwin then "open" else "xdg-open"} {}'
            set -g @thumbs-regexp-1 '(?:https?://|git@|git://|ssh://|ftp://|file:///)[^ ]+[^.,;:)\]> ]'
          '';
        }
        {
          plugin = inputs.sessionx.packages.${system}.default;
          extraConfig = ''
            set -g @sessionx-bind 'o'
          '';
        }
        {
          plugin = resurrect;
          extraConfig = ''
            # save/restore: prefix + Ctrl-s / prefix + Ctrl-r
            # re-launch nvim in panes where it was running on restore
            set -g @resurrect-strategy-nvim 'session'
          '';
        }
        {
          # continuum must load after resurrect
          plugin = continuum;
          extraConfig = ''
            set -g @continuum-restore 'on'
          '';
        }
      ];
      shortcut = "a";
    };
  };
}
