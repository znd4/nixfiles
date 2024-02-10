{ lib, pkgs, inputs, username, machine, ... }: {

  home.packages = [ pkgs.haskellPackages.kmonad ];
  systemd.user.services.kmonad = let
    keyboardMap = {
      "t470" = "/dev/input/by-path/platform-i8042-serio-0-event-kbd";
    };
  in {
    Service = {
      ExecStart = lib.strings.escapeShellArgs [
        "${pkgs.haskellPackages.kmonad}/bin/kmonad"
        "--config"
        "${inputs.dotfiles}/xdg-config/.config/kmonad/config.kbd"
      ];
      Restart = "always";
    };
    Install = { WantedBy = "multi-user.target"; };
    Unit = { Description = "kmonad"; };
  };
}
