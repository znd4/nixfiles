# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs, username, lib, config, pkgs, stateVersion, ... }: {

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      # outputs.overlays.additions
      # outputs.overlays.modifications
      # outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default
      inputs.kmonad.overlays.default

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
  home.username = username;

  xdg.configFile = let dotConfig = "${inputs.dotfiles}/xdg-config/.config";
  in {
    "nvim/" = {
      source = "${dotConfig}/nvim/";
      #recursive=true;
    };
    # "fish/"={source= "${inputs.dotfiles}/fish/.config/fish/"; enable=false;};
    "starship.toml".source = "${dotConfig}/starship.toml";
    "wezterm/wezterm.lua".source = "${dotConfig}/wezterm/wezterm.lua";
    # "direnv/direnvrc".source = "${dotConfig}/direnv/direnvrc";
    "direnv/direnvrc".text = builtins.readFile "${dotConfig}/direnv/direnvrc";
    "git/" = {
      recursive = false;
      source = "${dotConfig}/git/";
    };
  };

  programs.git.lfs.enable = true;

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  home.packages = with pkgs; [
    kmonad
    asdf
    bat
    broot
    cargo
    clipboard-jh
    delta
    fd
    gcc
    gh
    git
    gnumake
    go
    htop
    just
    kubectl
    lazygit
    lua-language-server
    neovim
    neovim-remote
    nixfmt
    nodejs
    opam
    podman-compose
    pre-commit
    python-launcher
    ripgrep
    ruff
    rustc
    skim
    stow
    stylua
    thefuck
    unzip
    wget
    xh
    zig
    zoxide
    zsh
    (python3.withPackages (ps: with ps; [ pre-commit ]))
    (buildEnv {
      name = "myScripts";
      paths = [ "${inputs.dotfiles}/scripts/.local" ];
    })
  ];

  programs.skim.enable = true;
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

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = stateVersion;
}
