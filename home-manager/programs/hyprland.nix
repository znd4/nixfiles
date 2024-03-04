{
  lib,
  inputs,
  pkgs,
  system,
  ...
}:
let
  hyprland = inputs.hyprland.packages.${system}.hyprland;
  plugins = inputs.hyprland-plugins.packages.${system};
  mainMod = "SUPER";
  terminal = "wezterm";
  fileManager = "dolphin";
  notificationDaemon = "dunst"; # mako, swaync
  wallpaperApp = "hyprpaper"; # swaybg, wpaperd, mpvpaper, swww
  menu = "wofi --show drun";

  yt = pkgs.writeShellScript "yt" ''
    notify-send "Opening video" "$(wl-paste)"
    mpv "$(wl-paste)"
  '';

  enabled = builtins.elem system [
    "x86_64-linux"
    "aarch_64-linux"
  ];
in
if !enabled then
  { }
else
  {
    imports = [
      inputs.hypridle.homeManagerModules.default
      inputs.hyprlock.homeManagerModules.default
    ];
    services.hypridle = {
      # https://github.com/hyprwm/hypridle/blob/main/nix/hm-module.nix
      enable = true;
      lockCmd = "hyprlock";
    };
    programs.hyprlock = {
      # https://github.com/hyprwm/hyprlock/blob/main/nix/hm-module.nix
      enable = true;
    };

    home.packages = with pkgs; [
      # menu bars
      waybar
      # (waybar.overrideAttrs (
      #   oldAttrs: { mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ]; }
      # ))
      # eww # https://github.com/elkowar/eww/

      pkgs.${notificationDaemon} # notifications

      # file manager
      pkgs.${fileManager}

      # Wallpapers
      pkgs.${wallpaperApp}

      # Brightness and audio controls
      pulseaudio
      brightnessctl
      playerctl

      # not sure if these are necessary
      # qt6
      # libsForQt5

      # https://wiki.hyprland.org/Useful-Utilities/Must-have/#authentication-agent
      polkit-kde-agent

      # just-in-case terminal
      kitty

      # Launchers
      rofi-wayland
      wofi
      bemenu
      fuzzel
      tofi
    ];

    systemd.user.services.polkit-agent-helper-1 = {
      Unit = {
        Description = "polkit-agent-helper-1";
        Wants = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.polkit-kde-agent}/libexec/polkit-agent-helper-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };

    wayland.windowManager.hyprland = {
      enable = true;
      package = hyprland;
      systemd.enable = true;
      xwayland.enable = true;
      plugins = [ ];
      settings = {

        exec-once = [
          wallpaperApp # # wallpaper
          "waybar" # menu bar
          notificationDaemon
          terminal # terminal (e.g. wezterm)
        ];

        monitor = [ ",preferred,auto,auto" ];

        env = [
          "XCURSOR_SIZE,24"
          "QT_QPA_PLATFORMTHEME,qt5ct" # change to qt6ct if you have that
        ];

        misc = {
          # disable_splash_rendering = true;
          # force_default_wallpaper = 1;
        };

        # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
        input = {
          kb_layout = "us";
          # kb_variant =
          # kb_model =
          # kb_options =
          # kb_rules =
          follow_mouse = 1;
          touchpad = {
            natural_scroll = false;
            disable_while_typing = true;
            # drag_lock = true;
          };
          sensitivity = 0; # -1.0 - 1.0, 0 means no modification.
        };

        general = {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more

          gaps_in = 5;
          gaps_out = 20;
          border_size = 2;
          col.active_border = "rgba(33ccffee) rgba(00ff99ee) 45deg";
          col.inactive_border = "rgba(595959aa)";

          layout = "dwindle";

          # resize with mouse
          resize_on_border = true;
          extend_border_grab_area = 15;

          # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
          allow_tearing = false;
        };

        decoration = {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more

          rounding = 10;

          blur = {
            enabled = true;
            size = 8;
            passes = 3;

            popups = true;
          };

          drop_shadow = true;
          shadow_range = 4;
          shadow_render_power = 3;
          col.shadow = "rgba(1a1a1aee)";
        };

        animations = {
          enabled = true;

          # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

          bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";

          animation = [
            "windows, 1, 7, myBezier"
            "windowsOut, 1, 7, default, popin 80%"
            "border, 1, 10, default"
            "borderangle, 1, 8, default"
            "fade, 1, 7, default"
            "workspaces, 1, 6, default"
          ];
        };

        # Example windowrule v1
        # windowrule = float, ^(kitty)$
        # Example windowrule v2
        # windowrulev2 = float,class:^(kitty)$,title:^(kitty)$
        # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more
        windowrulev2 = [
          "suppressevent maximize, class:.*" # You'll probably like this.

          # Automatically send wezterm to scratch workspace
          "float, class:^${terminal}$"
          "workspace special:${terminal}, class:^${terminal}$"
          "size 99% 50%, class:^${terminal}$"
          "move 0.5% 0%, class:^${terminal}$"
        ];

        misc = {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more
          force_default_wallpaper = -1; # Set to 0 or 1 to disable the anime mascot wallpapers
        };

        dwindle = {
          # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
          pseudotile = true; # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
          preserve_split = true; # you probably want this
        };
        master = {
          # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
          new_is_master = true;
        };

        gestures = {
          workspace_swipe = true;
          workspace_swipe_forever = true;
          workspace_swipe_numbered = true;
        };

        windowrule =
          let
            f = regex: "float, ^(${regex})$";
          in
          [
            (f "org.gnome.Calculator")
            (f "org.gnome.Nautilus")
            (f "pavucontrol")
            (f "nm-connection-editor")
            (f "blueberry.py")
            (f "org.gnome.Settings")
            (f "org.gnome.design.Palette")
            (f "Color Picker")
            (f "xdg-desktop-portal")
            (f "xdg-desktop-portal-gtk")
            (f "transmission-gtk")
            # "workspace 7, title:Spotify"
          ];

        bind =
          let
            binding =
              mod: cmd: key: arg:
              "${mod}, ${key}, ${cmd}, ${arg}";
            mvfocus = binding "SUPER" "movefocus";
            ws = binding "SUPER" "workspace";
            resizeactive = binding "SUPER CTRL" "resizeactive";
            mvactive = binding "SUPER ALT" "moveactive";
            mvtows = binding "SUPER SHIFT" "movetoworkspace";
            arr = [
              1
              2
              3
              4
              5
              6
              7
              8
              9
            ];
          in
          # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
          [
            "CTRL ALT, F, togglespecialworkspace, ${terminal}"
            "SUPER, grave, togglespecialworkspace, ${terminal}"
            "SUPER, Return, exec, xterm" # xterm is a symlink, not actually xterm
            "ALT, G, exec, vivaldi"
            "${mainMod}, E, exec, ${fileManager}"
            "${mainMod}, R, exec, ${menu}"

            # youtube
            ", XF86Launch1,  exec, ${yt}"

            "ALT, Tab, focuscurrentorlast"
            "CTRL ALT, Delete, exit"
            "ALT, Q, killactive"
            "${mainMod}, S, togglefloating"
            "${mainMod}, D, fullscreen"
            "${mainMod}, O, fakefullscreen"
            "${mainMod}, P, togglesplit"
            "${mainMod}, E, pseudo"

            "${mainMod}, L, exec, hyprlock"

            # Scroll through existing workspaces with mainMod + scroll
            "${mainMod}, mouse_down, workspace, e+1"
            "${mainMod}, mouse_up, workspace, e-1"

            (mvfocus "k" "u")
            (mvfocus "j" "d")
            (mvfocus "l" "r")
            (mvfocus "h" "l")
            (ws "left" "e-1")
            (ws "right" "e+1")
            (mvtows "left" "e-1")
            (mvtows "right" "e+1")
            (resizeactive "k" "0 -20")
            (resizeactive "j" "0 20")
            (resizeactive "l" "20 0")
            (resizeactive "h" "-20 0")
            (mvactive "k" "0 -20")
            (mvactive "j" "0 20")
            (mvactive "l" "20 0")
            (mvactive "h" "-20 0")
          ]
          ++ (map (i: ws (toString i) (toString i)) arr)
          ++ (map (i: mvtows (toString i) (toString i)) arr);

        bindel =
          let
            brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
            pactl = "${pkgs.pulseaudio}/bin/pactl";
          in

          [
            ",XF86MonBrightnessUp,   exec, ${brightnessctl} set +5%"
            ",XF86MonBrightnessDown, exec, ${brightnessctl} set  5%-"
            ",XF86KbdBrightnessUp,   exec, ${brightnessctl} -d asus::kbd_backlight set +1"
            ",XF86KbdBrightnessDown, exec, ${brightnessctl} -d asus::kbd_backlight set  1-"
            ",XF86AudioRaiseVolume,  exec, ${pactl} set-sink-volume @DEFAULT_SINK@ +5%"
            ",XF86AudioLowerVolume,  exec, ${pactl} set-sink-volume @DEFAULT_SINK@ -5%"
          ];

        bindl =
          let
            playerctl = "${pkgs.playerctl}/bin/playerctl";
            pactl = "${pkgs.pulseaudio}/bin/pactl";
          in
          [
            ",XF86AudioPlay,    exec, ${playerctl} play-pause"
            ",XF86AudioStop,    exec, ${playerctl} pause"
            ",XF86AudioPause,   exec, ${playerctl} pause"
            ",XF86AudioPrev,    exec, ${playerctl} previous"
            ",XF86AudioNext,    exec, ${playerctl} next"
            ",XF86AudioMicMute, exec, ${pactl} set-source-mute @DEFAULT_SOURCE@ toggle"
          ];

        bindm = [
          "SUPER, mouse:273, resizewindow"
          "SUPER, mouse:272, movewindow"
        ];

        plugin = {
          hyprbars = {
            bar_color = "rgb(2a2a2a)";
            bar_height = 28;
            col_text = "rgba(ffffffdd)";
            bar_text_size = 11;
            bar_text_font = "Ubuntu Nerd Font";

            buttons = {
              button_size = 0;
              "col.maximize" = "rgba(ffffff11)";
              "col.close" = "rgba(ff111133)";
            };
          };
        };
      };
    };
  }
