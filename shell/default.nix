{ lib, config, pkgs, inputs, ... }: {

  programs.direnv = {
    enable = true;
  };
  programs.fish.enable = lib.mkDefault true;
  programs.starship.enable = true;
  programs.skim.fuzzyCompletion = true;


  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withPython3 = true;
    withNodeJs = true;
  };

  environment.systemPackages = with pkgs; [
    inputs.home-manager.packages.${pkgs.system}.default
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
    podman-compose
    python-launcher
    python3
    (python3.withPackages (ps: with ps; [
        pre-commit
    ]))
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
