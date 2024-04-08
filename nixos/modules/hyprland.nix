{
  inputs,
  pkgs,
  system,
  ...
}:
{
  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    # trusted-substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };
  services.xserver.displayManager.sddm = {
    enable = true;
  };

  services.blueman.enable = true;

  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${system}.hyprland;
    xwayland.enable = true;
  };
  environment.sessionVariables = {
    # to prevent invisible cursor
    WLR_NO_HARDWARE_CURSORS = "1";
    # electron apps should use wayland
    NIXOS_OZONE_WL = "1";
  };

  hardware = {
    opengl.enable = true;
    nvidia.modesetting.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
  };

  xdg.mime = {
    enable = true;
    defaultApplications =
      let
        vivaldi = [
          # "${pkgs.vivaldi}/share/applications/vivaldi-stable.desktop"
          "vivaldi-stable.desktop"
        ];
      in
      {
        "text/html" = vivaldi;
        "application/xhtml+xml" = vivaldi;
        "x-scheme-handler/http" = vivaldi;
        "x-scheme-handler/https" = vivaldi;
      };
  };

  security = {
    polkit.enable = true;
    pam.services = {
      sddm.enableKwallet = true;
      hyprlock = { };
      args = { };
    };
  };

  services = {
    gvfs.enable = true;
    devmon.enable = true;
    udisks2.enable = true;
    upower.enable = true;
    power-profiles-daemon.enable = true;
    accounts-daemon.enable = true;
  };
}
