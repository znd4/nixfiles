{
  pkgs,
  inputs,
  system,
  seshClConfig,
  ...
}:
{
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
        		--header '  ^a all ^t tmux ^x zoxide ^f find' \
        		--bind 'tab:down,btab:up' \
        		--bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list)' \
        		--bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t)' \
        		--bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z)' \
        		--bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)'
      )"

      bind -n M-c run-shell "_sesh-cl-fuzzy \
        --gitlab [${
          lib.strings.concatStringsSep " " seshClConfig.gitlabHosts
        }] \
        --github_orgs [${
          lib.strings.concatStringsSep " " seshClConfig.githubOrgs
        }] \
        --parent-directory [${
          lib.strings.concatStringsSep " " seshClConfig.parentDirectories
        }]
      "


      # use alt+vim movement between panes
      bind -n M-h select-pane -L
      bind -n M-j select-pane -D
      bind -n M-k select-pane -U
      bind -n M-l select-pane -R

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

      # floating pane
      bind -n M-f if-shell -F '#{==:#{session_name},floating}' {
          detach-client
      } {
          set -gF '@last_session_name' '#S'
          popup -d '#{pane_current_path}' -xC -yC -w80% -h80% -E 'tmux new -A -s floating'
      }

      bind ! if-shell -F '#{!=:#{session_name},floating}' {
          break-pane
      } {
          run-shell 'bash -c "tmux break-pane -s floating -t \"$(tmux show -gvq '@last_session_name'):\""'
      }

      bind @ if-shell -F '#{!=:#{session_name},floating}' {
          break-pane -d
      } {
          run-shell 'bash -c "tmux break-pane -d -s floating -t \"$(tmux show -gvq '@last_session_name'):\""'
      }
    '';

    plugins = with pkgs.tmuxPlugins; [
      battery
      catppuccin
      pain-control
      sensible
      tmux-fzf
      {
        plugin = tmux-thumbs;
        # extraConfig = ''
        #   set -g @thumbs-command 'tmux run-shell "echo -n {} | #{@clipboard} && tmux display-message \"Copied to clipboard\""'
        # '';
      }
      {
        plugin = inputs.sessionx.packages.${system}.default;
        extraConfig = ''
          set -g @sessionx-bind 'o'
        '';
      }
    ];
    shortcut = "a";
  };
}
