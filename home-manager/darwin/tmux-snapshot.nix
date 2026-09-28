{
  config,
  pkgs,
  ...
}:
# Save the Claude Code session UUID of each tmux pane at login and every 30
# minutes. After a tmux crash, only sessions that started in the last 30
# minutes can be missing. This is the tmux port of ./herdr-snapshot.nix.
#
# `workmux resurrect` runs `claude --continue` and restores only one agent per
# worktree. `tmux-restore` resumes each pane by its exact UUID.
#
# See ../bin/tmux-snapshot.py for the output format and how it finds each UUID.
let
  # Use the Nix python3, not `uv run`. The reason is in ./herdr-snapshot.nix.
  tmuxSnapshot = pkgs.writeShellApplication {
    name = "tmux-snapshot";
    # The tmux client must match the server version, so use the tmux that
    # programs.tmux installs. `ps` comes from /bin, which launchd puts on PATH.
    runtimeInputs = [ config.programs.tmux.package ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../bin/tmux-snapshot.py} "$@"
    '';
  };

  tmuxRestore = pkgs.writeShellApplication {
    name = "tmux-restore";
    runtimeInputs = [ config.programs.tmux.package ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../bin/tmux-restore.py} "$@"
    '';
  };

  logDir = "${config.home.homeDirectory}/Library/Logs";
in
{
  home.packages = [
    tmuxSnapshot
    tmuxRestore
  ];

  home.file.".claude/skills/tmux-restore/SKILL.md".source =
    ../claude-skills/tmux-restore/SKILL.md;

  launchd.agents.tmux-snapshot = {
    enable = true;
    config = {
      ProgramArguments = [ "${tmuxSnapshot}/bin/tmux-snapshot" ];
      StartInterval = 1800;
      RunAtLoad = true;
      # The job prints nothing on success or when no tmux server runs.
      # Any output in this file is a fault.
      StandardOutPath = "${logDir}/tmux-snapshot.log";
      StandardErrorPath = "${logDir}/tmux-snapshot.log";
      ProcessType = "Background";
    };
  };
}
