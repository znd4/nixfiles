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

  # Runs the editor in a pane of a hidden window. edit-scrollback swaps that
  # pane into the place of the original pane. When the editor exits, this
  # script swaps the original pane back, and the hidden window closes.
  edit-scrollback-editor = pkgs.writeShellScript "tmux-edit-scrollback-editor" ''
    orig=$1 file=$2
    editor=''${EDITOR:-vi}
    case "$(basename "''${editor%% *}")" in
      *vi | *vim) $editor + "$file" ;; # start at the bottom
      *) $editor "$file" ;;
    esac
    rm -f "$file"
    tmux swap-pane -s "$TMUX_PANE" -t "$orig" \; select-pane -t "$orig"
  '';

  edit-scrollback = pkgs.writeShellScript "tmux-edit-scrollback" ''
    orig=$1
    file=$(mktemp "''${TMPDIR:-/tmp}/tmux-scrollback.XXXXXX")
    # -J joins wrapped lines, but it also keeps trailing spaces. Remove them,
    # then remove the empty lines at the end of the output.
    tmux capture-pane -p -J -S - -t "$orig" |
      ${pkgs.gawk}/bin/awk '{ sub(/[ \t]+$/, "") } NF { for (; n > 0; n--) print ""; print; next } { n++ }' > "$file"
    session=$(tmux display-message -p -t "$orig" '#{session_id}')
    dir=$(tmux display-message -p -t "$orig" '#{pane_current_path}')
    new=$(tmux new-window -d -P -F '#{pane_id}' -t "$session:" -n scrollback -c "$dir" \
      ${edit-scrollback-editor} "$orig" "$file")
    tmux swap-pane -s "$new" -t "$orig" \; select-pane -t "$new"
  '';

  # Moves a pane into a new session. new-session needs a first window, so the
  # script puts the pane after that window and then closes it. The result has
  # no extra shell. An existing session name gets the pane as a new window.
  #
  # The popup closes when the script exits, and that hides errors. So the
  # script writes a log to ~/.local/state/tmux-split-to-session/log (set
  # TMUX_SPLIT_LOG_DIR to change the directory). Each run adds one block.
  split-to-session = pkgs.writeShellScript "tmux-split-to-session" ''
    PATH=${pkgs.coreutils}/bin:$PATH
    pane=$1

    log_dir=''${TMUX_SPLIT_LOG_DIR:-$HOME/.local/state/tmux-split-to-session}
    log=$log_dir/log
    mkdir -p "$log_dir"
    # Rotate the log when it reaches 100 KB. Keep log.1 to log.3.
    if [ -f "$log" ] && [ "$(stat -c %s "$log")" -ge 102400 ]; then
      for i in 2 1; do
        [ -f "$log.$i" ] && mv -f "$log.$i" "$log.$((i + 1))"
      done
      mv -f "$log" "$log.1"
    fi
    log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$log"; }

    printf '\n=== %s ===\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >>"$log"
    log "args: $(printf '%q ' "$@")"
    log "PWD: $PWD"
    log "TMUX: ''${TMUX:-<unset>}"
    log "TMUX_PANE: ''${TMUX_PANE:-<unset>}"
    log "TERM: ''${TERM:-<unset>}"
    t0=no t1=no t2=no
    [ -t 0 ] && t0=yes
    [ -t 1 ] && t1=yes
    [ -t 2 ] && t2=yes
    log "tty: $(tty 2>&1); stdin tty: $t0; stdout tty: $t1; stderr tty: $t2"

    # Keep the popup terminal on fd 3 for gum and for error messages. Send all
    # other stderr to the log.
    exec 3>&2 2>>"$log"
    trap 'rc=$?; log "ERR: line $LINENO: $BASH_COMMAND (exit $rc)"' ERR
    errf=$(mktemp "''${TMPDIR:-/tmp}/tmux-split-to-session.XXXXXX")
    trap 'rm -f "$errf"' EXIT

    # Runs a command and logs its command line, exit status, stdout and
    # stderr. The stdout goes into $out.
    run() {
      local rc=0
      out=$("$@" 2>"$errf" 3>&-) || rc=$?
      log "run: $(printf '%q ' "$@")-> exit $rc, stdout: $out"
      if [ -s "$errf" ]; then log "  stderr: $(cat "$errf")"; fi
      return $rc
    }

    # Shows the error in the popup, then exits. If stdin is a terminal, it
    # waits for Enter first. The popup has only 3 rows, so keep the text short.
    fail() {
      log "FAIL: $*"
      err=$(head -n 1 "$errf")
      printf '%s failed: %s\nLog: %s\n' "$*" "$err" "''${log/#$HOME/\~}" >&3
      if [ -t 0 ]; then
        printf 'Press Enter to close.' >&3
        read -r || true
      fi
      tmux display-message "split-to-session: $* failed: $err" 3>&-
      exit 1
    }

    # Start from the window name when someone set it. An auto-renamed window
    # has the name of its program, which makes a poor session name. Tmux
    # changes ":" and "." in a session name, so do that here.
    default=""
    run tmux display-message -p -t "$pane" '#{automatic-rename}' || fail "display-message"
    if [ "$out" = 0 ]; then
      run tmux display-message -p -t "$pane" '#{window_name}' || fail "display-message"
      default=$(printf '%s' "$out" | tr ':.' '__')
    fi
    log "default: $default"

    # gum draws its UI on stderr, so give it the popup terminal on fd 3.
    gum_rc=0
    name=$(${pkgs.gum}/bin/gum input --placeholder "new session name" --value "$default" 2>&3 3>&-) || gum_rc=$?
    log "gum: exit $gum_rc, name: $name"
    if [ -z "$name" ]; then
      log "empty name, exit 0"
      exit 0
    fi

    if run tmux has-session -t "=$name"; then
      log "branch: existing session"
      run tmux break-pane -d -a -s "$pane" -t "=$name:" || fail "break-pane"
    else
      log "branch: new session"
      run tmux new-session -d -P -F '#{window_id}' -s "$name" -c "$PWD" || fail "new-session"
      first=$out
      run tmux break-pane -d -a -s "$pane" -t "$first" || fail "break-pane"
      run tmux kill-window -t "$first" || fail "kill-window"
      run tmux move-window -r -t "=$name:" || fail "move-window"
    fi
    log "done"
  '';

  # The scripts look up fzf and jq on PATH. The tmux server PATH can lack
  # them, so postInstall adds the Nix store paths to the start of PATH in
  # each script.
  claude-hatch = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "claude-hatch";
    version = "1.5.0-znd4";
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
        bind -n M-d run-shell "s=$(
          sesh list -tzs | fzf-tmux -p 55%,60% \
          		--no-sort --border-label ' sesh ' --prompt '⚡  ' \
          		--header '  ^a all ^t tmux ^x zoxide ^f find ^d delete' \
          		--bind 'tab:down,btab:up' \
          		--bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list)' \
          		--bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t)' \
          		--bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z)' \
          		--bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
          		--bind 'ctrl-d:execute-silent(tmux kill-session -t {})+reload(sesh list -tzs)'
        ); [ -z \"\$s\" ] || sesh connect \"\$s\""

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

        # On macOS, tmux-sensible sets an empty default-command to run $SHELL.
        # The tmux server's $SHELL is /bin/sh, so panes would start sh, not fish.
        # exec replaces the tmux shell with fish, so fish is the pane process.
        # tmux-resurrect then sees the program that runs in fish.
        set -g default-command "exec ${pkgs.fish}/bin/fish"

        # open the current pane's scrollback in $EDITOR, in place of the pane
        bind e run-shell '${edit-scrollback} #{pane_id}'

        # prefix S: ask for a name, then move the current pane into a new
        # session (the session starts in the pane's directory)
        bind S display-popup -E -w 50 -h 5 -d "#{pane_current_path}" '${split-to-session} #{pane_id}'
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
            # Show the window name when it was set on purpose (automatic-rename
            # is off, for example in a workmux window). Otherwise show the pane
            # title, which Claude sets to its session summary.
            set -g @catppuccin_window_text ' #{?automatic-rename,#T,#W}'
            set -g @catppuccin_window_current_text ' #{?automatic-rename,#T,#W}'

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
