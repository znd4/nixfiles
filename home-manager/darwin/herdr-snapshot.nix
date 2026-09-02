{
  inputs,
  system,
  config,
  pkgs,
  ...
}:
# Save the herdr session state every 30 minutes, so that a crash of the herdr
# server cannot lose more than 30 minutes of work.
#
# herdr keeps the workspace labels, the layout and the working directories
# across a crash of its server. It does not keep the mapping from a pane to the
# Claude Code session UUID that ran in it. Without that mapping you cannot run
# `claude --resume <uuid>` after the crash, and each killed session becomes
# unreachable. One crash killed 12 sessions this way.
#
# `herdr api snapshot` prints all of the data — the agents with their session
# UUIDs, and the workspaces, tabs, panes and layouts. The job therefore only
# writes that output to disk. See ../bin/herdr-snapshot.py for the output
# format and the file names.
let
  herdr = inputs.herdr.packages.${system}.default;

  # ../bin/herdr-snapshot.py is a self-contained uv script: it has the
  # `uv run --script` shebang and a PEP 723 metadata block, so that you can also
  # run it by hand. The job below runs it with the Nix python instead of with
  # `uv run`, for two reasons. The script needs no PyPI package, and launchd
  # gives a job almost no environment: `uv run` would have to find or download a
  # Python interpreter, over a network that the TLS proxy of the company
  # intercepts, every 30 minutes and at each wake from sleep. The Nix python
  # needs no network and always gives the same result.
  herdrSnapshot = pkgs.writeShellApplication {
    name = "herdr-snapshot";
    runtimeInputs = [
      herdr
      pkgs.coreutils
    ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../bin/herdr-snapshot.py} "$@"
    '';
  };

  logDir = "${config.home.homeDirectory}/Library/Logs";
in
{
  home.packages = [ herdrSnapshot ];

  launchd.agents.herdr-snapshot = {
    enable = true;
    config = {
      ProgramArguments = [ "${herdrSnapshot}/bin/herdr-snapshot" ];

      # Every 30 minutes. launchd delays a missed run until the next wake, which
      # is the behaviour we want: a sleeping laptop runs no sessions to save.
      StartInterval = 1800;

      # Save a snapshot at login too. The first 30 minutes after a restart are
      # the period in which the sessions of the day appear.
      RunAtLoad = true;

      # The job prints nothing when it succeeds, and prints nothing when the
      # herdr server is stopped. Anything in this file is therefore a fault.
      StandardOutPath = "${logDir}/herdr-snapshot.log";
      StandardErrorPath = "${logDir}/herdr-snapshot.log";

      ProcessType = "Background";
    };
  };
}
