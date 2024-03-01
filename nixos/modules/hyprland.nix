{ inputs, pkgs, ... }:
{
  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  services.xserver.displayManager.startx.enable = true;

  programs.hyprland = {
    enable = true;
    nvidiaPatches = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
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
    pam.services.ags = { };
  };

  environment.systemPackages =
    with pkgs;
    [
      waybar # simple menu bar
      (waybar.overrideAttrs (
        oldAttrs: { mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ]; }
      ))
      eww # https://github.com/elkowar/eww/
      dunst # notifications

      # Wallpapers
      hyprpaper
      swaybg
      wpaperd
      mpvpaper
      swww

      # Launchers
      rofi-wayland
      wofi
      bemenu
      fuzzel
      tofi
    ]
    ++ (with gnome; [
      loupe
      adwaita-icon-theme
      nautilus
      baobab
      gnome-calendar
      gnome-boxes
      gnome-system-monitor
      gnome-control-center
      gnome-weather
      gnome-calculator
      gnome-clocks
      gnome-software # for flatpak
      wl-gammactl
      wl-clipboard
      wayshot
      pavucontrol
      brightnessctl
      swww
    ]);

  systemd = {
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
  };

  services = {
    gvfs.enable = true;
    devmon.enable = true;
    udisks2.enable = true;
    upower.enable = true;
    power-profiles-daemon.enable = true;
    accounts-daemon.enable = true;
    gnome = {
      evolution-data-server.enable = true;
      glib-networking.enable = true;
      gnome-keyring.enable = true;
      gnome-online-accounts.enable = true;
    };
  };
}
