{
  pkgs,
  inputs,
  system,
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
    terminal = "screen-256color";
    tmuxinator.enable = true;
    tmuxp.enable = true;
    extraConfig = ''
      bind-key "T" run-shell "sesh connect $(
        sesh list -tz | fzf-tmux -p 55%,60% \
        		--no-sort --border-label ' sesh ' --prompt '⚡  ' \
        		--header '  ^a all ^t tmux ^x zoxide ^f find' \
        		--bind 'tab:down,btab:up' \
        		--bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list)' \
        		--bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t)' \
        		--bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z)' \
        		--bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)'
      )"
      # vi mode
      bind P paste-buffer
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      unbind -T copy-mode-vi Enter
      bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel 'cb copy'
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'cb copy'
      bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'cb copy'


      unbind r
      bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded ~/.tmux.conf"

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
          popup -d '#{pane_current_path}' -xC -yC -w70% -h70% -E 'tmux new -A -s floating'
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
        extraConfig = ''
          set -g @thumbs-command 'echo -n {} | cb copy && tmux display-message "Copied to clipboard"'
        '';
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