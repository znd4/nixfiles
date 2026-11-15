{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf pkgs.stdenv.isLinux {
    home.homeDirectory = "/home/" + config.home.username;
    home.packages = with pkgs; [
      #appimageTools

      appimage-run
      mpv-unwrapped
      rpi-imager
      signal-desktop
      zoom-us
      podman-desktop
    ];
    # Nicely reload system units when changing configs
    systemd.user.startServices = "sd-switch";
  };
}
