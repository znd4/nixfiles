# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs, outputs, username, lib, config, pkgs, stateVersion, ... }: {
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
      # outputs.overlays.additions
      # outputs.overlays.modifications
      # outputs.overlays.unstable-packages

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
    username = username;
    homeDirectory = "/home/" + username;
  };

  xdg.configFile = let dotConfig = "${inputs.dotfiles}/xdg-config/.config";
  in {
    "nvim/" = {
      source = "${dotConfig}/nvim/";
      #recursive=true;
    };
    # "fish/"={source= "${inputs.dotfiles}/fish/.config/fish/"; enable=false;};
    # "starship.toml".source = "${dotConfig}/starship.toml";
    "wezterm/wezterm.lua".source = "${dotConfig}/wezterm/wezterm.lua";
    # "direnv/direnvrc".source = "${dotConfig}/direnv/direnvrc";
    "direnv/direnvrc".text = builtins.readFile "${dotConfig}/direnv/direnvrc";
    "git/".source = "${dotConfig}/git/";
  };

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  home.packages = with pkgs; [
    appimage-run
    httpie
    kubectl
    lua-language-server
    nixfmt
    pre-commit
    ruff
  ];

  programs.zsh.enable = true;
  # Enable home-manager and git
  programs.fzf = {
    enable = true;
    tmux.enableShellIntegration = true;
  };
  programs.home-manager.enable = true;
  programs.fish = {
    enable = true;
    # plugins = [
    # {
    #     name = "fzf-fish";
    #   src = pkgs.fetchFromGithub{owner="patrickf1"; repo="fzf.fish";};
    # }
    # ];
    shellAbbrs = { ky = "kubectl get -o yaml"; };
    shellAliases = {
      nix = "NO_COLOR=1 command nix";
      bathelp = "bat -l help";
      bh = "bat -l help";
      g = "git";
      by = "bat -l yaml";
      k = "kubectl";
    };
    interactiveShellInit = ''
      fish_vi_key_bindings
    '';
  };

  programs.starship = { enable = true; };
  programs.zoxide.enable = true;
  programs.direnv.enable = true;
  programs.k9s.enable = true;

  programs.git.enable = false;
  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [
      tmux-thumbs
      pain-control
      sensible
      catppuccin
    ];
    shortcut = "a";
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = stateVersion;
}
