{
  pkgs,
  inputs,
  lib,
  config,
  username,
  ...
}: let
  neovim_python = pkgs.python3.withPackages (ps: with ps; [pynvim debugpy]);
in {
  xdg.configFile = {
    "nvim/lazy-lock.json".source = (
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/home-manager/programs/neovim/lazy-lock.json"
    );
    # "nvim/lazy-lock.json".enable = false;
    "nvim/".source = "${inputs.dotfiles}/xdg-config/.config/nvim/";
    "nvim/".recursive = true;
  };
  home.sessionVariables = {
    NVIM_PYTHON = "${neovim_python}/bin/python";
  };
  nixpkgs.overlays = [inputs.nixd.overlays.default];
  home.packages = with pkgs; [neovim-remote];
  programs.neovim = {
    enable = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    extraLuaPackages = ps:
      with ps; [
        jsregexp
      ];
    extraPackages = with pkgs; [
      gcc
      isort
      nil
      neovim-remote
      lua-language-server
      marksman
      nixd
      prettierd
      ruff
      rust-analyzer-unwrapped
    ];
  };
}
