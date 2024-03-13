{ pkgs, ... }:
{
  home.packages = with pkgs; [ hydroxide ];
  # TODO: create aliases for hydroxide that set `HYDROXIDE_BRIDGE_PASS` 
  # using values from `op read ...`
  # map `hostname` to the `op` password ID
  systemd.user.services.hydroxide = {
    Unit = {
      Description = "Open source protonmail bridge server";
      Wants = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.hydroxide}/bin/hydroxide serve";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
}
