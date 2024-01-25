# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs
, outputs
, username
, lib
, config
, pkgs
, stateVersion
, ...
}: {
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
      # Workaround for https://github.com/nix-community/home-manager/issues/2942
      allowUnfreePredicate = _: true;
    };
  };

  # TODO: Set your username
  home = {
    username = "your-username";
    homeDirectory = "/home/your-username";
  };

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  # home.packages = with pkgs; [ steam ];

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;
  programs.git = {
    enable = true;
    config = [
      {
        init.defaultBranch = "main";
        user = {
          name = "Zane Dufour";
          email = "zane@znd4.dev";
        };
        push.autoSetupRemote = true;
        pull.rebase = false;
      }
      {
        alias = {
          a = "add";
          pl = "pull";
          c = "commit";
          cm = "commit";
          co = "checkout";
          ck = "checkout";
          s = "status";
          ps = "push";
          d = "diff";
        };
      }
      # delta configuration
      {
        core = {
          pager = "delta";
        };
        interactive = {
          diffFilter = "delta --color-only";
        };
        delta = {
          pager = "less";
          navigate = true;
          light = false;
          side-by-side = true;
        };
        pager = {
          diff = "delta";
          log = "delta";
          reflog = "delta";
        };
        diff = {
          colorMoved = "default";
          pager = "delta";
        };
      }
    ];

  };
  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [ tmux-thumbs pain-control sensible catppuccin ];
    shortcut = "screen-256color";
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = stateVersion;
}
