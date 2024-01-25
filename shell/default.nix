{ lib, config, pkgs, ... }: {

  programs.direnv = {
    enable = true;
  };
  programs.fish.enable = lib.mkDefault true;
  programs.starship.enable = true;
  programs.skim.fuzzyCompletion = true;
  programs.home-manager.enable = true;


  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withPython3 = true;
    withNodeJs = true;
  };

  environment.systemPackages = with pkgs; [
    asdf
    bat
    broot
    cargo
    delta
    fd
    gcc
    gh
    git
    gnumake
    go
    htop
    just
    lazygit
    nodejs
    opam
    python-launcher
    python3
    ripgrep
    rustc
    skim
    stow
    stylua
    thefuck
    unzip
    wget
    zig
    zoxide
    zsh
  ];
}
