{ pkgs, lib, inputs, username, ... }: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
  };
  nix.settings.experimental-features = "nix-command flakes";
  services.nix-daemon.enable = true;
  nixpkgs.overlays = [ inputs.kmonad.overlays.default ];
  launchd.agents = {
    kmonad = {
      script = lib.strings.escapeShellArgs [
        "kmonad"
        "${inputs.dotfiles}/xdg-config/.config/kmonad/config.kbd"
      ];
      path = [ pkgs.kmonad ];
      serviceConfig = {
        UserName = "root";
        KeepAlive = true;
      };
    };
  };
}
