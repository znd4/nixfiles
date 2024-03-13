{ pkgs, ... }:
{
  home.packages = with pkgs; [ hydroxide ];
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
