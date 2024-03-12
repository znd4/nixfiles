{
  inputs,
  pkgs,
  system,
  ...
}:
{

  services.xserver.displayManager.sddm = {
    enable = true;
  };

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

  security = {
    polkit.enable = true;
    pam.services = {
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
