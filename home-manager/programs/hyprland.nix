# TODO: fix iwd not reconnecting after suspend
# TODO: Implement automatic login, and test that it only works right after boot
{
  config,
  inputs,
  lib,
  pkgs,
  system,
  ...
}:
let
  mainMod = "SUPER";
  terminal = "alacritty";
  fileManager = "dolphin";
  notificationDaemon = "dunst"; # mako, swaync
  wallpaperApp = "hyprpaper"; # swaybg, wpaperd, mpvpaper, swww
  # menu = "bemenu-run";
  brightnessctlBin = "${pkgs.brightnessctl}/bin/brightnessctl";
  pactlBin = "${pkgs.pulseaudio}/bin/pactl";
  yt = pkgs.writeShellScript "yt" ''
    notify-send "Opening video" "$(wl-paste)"
    mpv "$(wl-paste)"
  '';

  enabled = builtins.elem system [
    "x86_64-linux"
    "aarch64-linux"
  ];
in
if !enabled then
  { }
else
  {
    nixpkgs.overlays = [
      # inputs.waybar.overlays.default
    ];
    imports = [ inputs.hyprland.homeManagerModules.default ];
    services.gnome-keyring.enable = true;
    services.hypridle = {
      # https://github.com/hyprwm/hypridle/blob/main/nix/hm-module.nix
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };
        listener = [
          {
            timeout = 150;
            onTimeout = "${brightnessctlBin} -s set 10";
            onResume = "${brightnessctlBin} -r ";
          }
          {
            timeout = 150; # 2.5min.
            onTimeout = "brightnessctl -sd rgb:kbd_backlight set 0"; # turn off keyboard backlight.
            onResume = "brightnessctl -rd rgb:kbd_backlight"; # turn on keyboard backlight.
          }
          {
            timeout = 300;
            onTimeout = "hyprctl dispatch exit";
          }
          {
            timeout = 380; # 5.5min
            onTimeout = "hyprctl dispatch dpms off"; # screen off when timeout has passed
            onResume = "hyprctl dispatch dpms on"; # screen on when activity is detected after timeout has fired.
          }
          {
            timeout = 600; # 10min
            onTimeout = "systemctl suspend-then-hybernate"; # suspend pc
          }
        ];
      };
    };
    programs.hyprlock = {
      # https://github.com/hyprwm/hyprlock/blob/main/nix/hm-module.nix
      enable = true;
      settings = {
        background = [ { path = "${inputs.self}/docs/tokyo_skyline.png"; } ];
      };
    };

    gtk = {
      enable = true;
      theme = {
        # https://github.com/Fausto-Korpsvart/Tokyo-Night-GTK-Theme/tree/master
        package = pkgs.tokyo-night-gtk;
        # https://github.com/Fausto-Korpsvart/Tokyo-Night-GTK-Theme/tree/master/themes
        name = "Tokyonight-Dark-BL";
      };
      iconTheme = {
        package = pkgs.tokyo-night-gtk;
        # https://github.com/Fausto-Korpsvart/Tokyo-Night-GTK-Theme/tree/master/icons
        name = "Tokyonight-Dark";
      };
      gtk3.extraConfig = {
        Settings = ''
          gtk-application-prefer-dark-theme=1
        '';
      };

      gtk4.extraConfig = {
        Settings = ''
          gtk-application-prefer-dark-theme=1
        '';
      };
    };

    home.packages = with pkgs; [
      # menu bars
      waybar
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

      # for managing wifi
      networkmanagerapplet

      # not sure if these are necessary
      # qt6
      # libsForQt5

      # clipboard
      wl-clipboard
      wl-clip-persist

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

    # enable clipboard support
    services.copyq.enable = true;

    # bluetooth
    services.blueman-applet.enable = true;

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
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        # ExecStart = "${pkgs.polkit-kde-agent}/libexec/polkit-kde-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };

    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = true;
      xwayland.enable = true;
      plugins = [ ];
      settings = {
        exec-once = [
          "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator & disown"
          wallpaperApp # # wallpaper
          "1password"
          "logseq"
          "waybar" # menu bar
          notificationDaemon
          # terminal # terminal (e.g. wezterm)
          "wl-clip-persist --clipboard both"
          terminal
        ];

        monitor = [ ",preferred,auto,auto" ];

        env = [
          "XCURSOR_SIZE,24"
          "QT_QPA_PLATFORMTHEME,qt6ct" # change to qt6ct if you have that
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
          follow_mouse = 2;
          touchpad = {
            natural_scroll = false;
            disable_while_typing = true;
            clickfinger_behavior = 1; # two finger right click
            # drag_lock = true;
          };
          sensitivity = 0; # -1.0 - 1.0, 0 means no modification.
        };

        general = {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more

          gaps_in = 5;
          gaps_out = 20;
          border_size = 2;
          # col.active_border = "rgba(33ccffee) rgba(00ff99ee) 45deg";
          # col.inactive_border = "rgba(595959aa)";

          layout = "dwindle";

          # resize with mouse
          # resize_on_border = true;
          # extend_border_grab_area = 15;

          # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
          allow_tearing = false;
        };

        decoration = {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more

          rounding = 5;

          blur = {
            enabled = true;
            size = 8;
            passes = 3;

            popups = true;
          };

          drop_shadow = true;
          shadow_range = 4;
          shadow_render_power = 3;
        };

        animations = {
          enabled = true;

          # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

          # bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
          #
          # animation = [
          #   "windows, 1, 7, myBezier"
          #   "windowsOut, 1, 7, default, popin 80%"
          #   "border, 1, 10, default"
          #   "borderangle, 1, 8, default"
          #   "fade, 1, 7, default"
          #   "workspaces, 1, 6, default"
          # ];
        };

        # Example windowrule v1
        # windowrule = float, ^(kitty)$
        # Example windowrule v2
        # windowrulev2 = float,class:^(kitty)$,title:^(kitty)$
        # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more
        windowrulev2 =
          let
            # weztermClass = "^org.wezfurlong.wezterm$";
            kittyClass = "^kitty$";
            alacrittyClass = "^Alacritty$";
          in
          [
            # "suppressevent, maximize, class:.*" # You'll probably like this.

            "fullscreen, class:^${alacrittyClass}$"
            # Automatically send wezterm to scratch workspace
            "workspace special:${terminal}, class:^${alacrittyClass}$"
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
            (f "pavucontrol")
            (f "nm-connection-editor")
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
            drun = builtins.concatStringsSep " " [
              "tofi-drun"
              "--font=${pkgs.nerdfonts}/share/fonts/truetype/NerdFonts/VictorMonoNerdFont-Italic.ttf"
              "--ascii-input=true"
              "--drun-launch=true"
            ];
            run = builtins.concatStringsSep " " [
              "tofi-run"
              "--font=${pkgs.nerdfonts}/share/fonts/truetype/NerdFonts/VictorMonoNerdFont-Italic.ttf"
              "--ascii-input=true"
              "|"
              "xargs"
              "-r"
              "hyprctl"
              "dispatch"
              "exec"
            ];
          in
          # Example binds, see https://wiki.hyprland.org/Configuring/Binds/ for more
          [
            "CTRL ALT, F, togglespecialworkspace, ${terminal}"
            "SUPER, grave, togglespecialworkspace, ${terminal}"
            "SUPER, Return, exec, ${terminal}" # xterm is a symlink, not actually xterm
            "ALT, G, exec, vivaldi"
            # "${mainMod}, E, exec, ${fileManager}"
            "ALT, SPACE, exec, ${drun}"
            "${mainMod}, R, exec, ${run}"

            # youtube
            ", XF86Launch1,  exec, ${yt}"

            # 1password
            "SUPER SHIFT, SPACE, exec, 1password --quick-access"

            "ALT, Tab, focuscurrentorlast"
            "CTRL ALT, Delete, exit"
            "ALT, Q, killactive"
            "${mainMod}, S, togglefloating"
            "${mainMod}, D, fullscreen"
            "${mainMod}, O, fakefullscreen"
            "${mainMod}, P, togglesplit"
            "${mainMod}, E, pseudo"

            "CTRL SUPER, Q, exec, hyprlock"

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

        bindel = [
          ",XF86MonBrightnessUp,   exec, ${brightnessctlBin} set +5%"
          ",XF86MonBrightnessDown, exec, ${brightnessctlBin} set  5%-"
          # keyboard backlight
          # ",XF86KbdBrightnessUp,   exec, ${brightnessctl} -d asus::kbd_backlight set +1"
          # ",XF86KbdBrightnessDown, exec, ${brightnessctl} -d asus::kbd_backlight set  1-"
          ",XF86AudioRaiseVolume,  exec, ${pactlBin} set-sink-volume @DEFAULT_SINK@ +5%"
          ",XF86AudioLowerVolume,  exec, ${pactlBin} set-sink-volume @DEFAULT_SINK@ -5%"
        ];

        bindl =
          let
            playerctl = "${pkgs.playerctl}/bin/playerctl";
          in
          [
            ",XF86AudioPlay,    exec, ${playerctl} play-pause"
            ",XF86AudioStop,    exec, ${playerctl} pause"
            ",XF86AudioPause,   exec, ${playerctl} pause"
            ",XF86AudioPrev,    exec, ${playerctl} previous"
            ",XF86AudioNext,    exec, ${playerctl} next"
            ",XF86AudioMicMute, exec, ${pactlBin} set-source-mute @DEFAULT_SOURCE@ toggle"
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
