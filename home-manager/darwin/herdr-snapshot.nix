{
  inputs,
  system,
  config,
  pkgs,
  ...
}:
# Save herdr session state every 30 minutes so a server crash cannot lose more
# than 30 minutes of session UUIDs.
#
# herdr keeps workspace labels, layout, and working directories across a crash.
# It does not keep the Claude Code session UUID for each pane. Without that
# UUID, `claude --resume <uuid>` cannot work, and each killed session becomes
# unreachable. One crash lost 12 sessions this way.
#
# See ../bin/herdr-snapshot.py for the output format, file names, and the
# pid-based UUID recovery that supplements `herdr api snapshot`.
let
  herdr = inputs.herdr.packages.${system}.default;

  # The script has a `uv run --script` shebang and PEP 723 metadata, so you
  # can run it by hand. The launchd job uses the Nix python3 instead because
  # the script needs no PyPI packages, and launchd gives jobs almost no
  # environment -- `uv run` would need to find or download a Python interpreter
  # over the company TLS proxy every 30 minutes and at each wake. The Nix
  # python needs no network and always gives the same result.
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

      # Every 30 minutes. launchd delays a missed run until the next wake.
      # A sleeping laptop runs no sessions to save.
      StartInterval = 1800;

      # Also snapshot at login. Most sessions appear in the first 30 minutes
      # after a restart.
      RunAtLoad = true;

      # The job prints nothing on success or when the server is stopped.
      # Any output in this file is a fault.
      StandardOutPath = "${logDir}/herdr-snapshot.log";
      StandardErrorPath = "${logDir}/herdr-snapshot.log";

      ProcessType = "Background";
    };
  };
}
