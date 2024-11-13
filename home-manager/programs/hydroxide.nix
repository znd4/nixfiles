{ pkgs, lib, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      hydroxide = pkgs.buildGoModule.override { go = pkgs.go_1_23; } {
        version = "znd4-fork";
        pname = "hydroxide";
        src = pkgs.fetchFromGitHub {
          owner = "znd4";
          repo = "hydroxide";
          rev = "personal-fork";
          sha256 = "sha256-lHNq08XJvPVZzKIvSzd2o2nwUIf+sZI8tcUA+Q9HhEE=";
        };
        vendorHash = "sha256-YUkggBm2OPD2W8Qo1woG4l7tsh5bLeVehNJ8N0ZlcqU=";

        doCheck = false;

        subPackages = [ "cmd/hydroxide" ];
        # vendorHash = lib.fakeHash;
      };
    })
  ];
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
