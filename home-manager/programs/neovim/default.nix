{ pkgs, inputs, lib, config, username, ... }:
{

  xdg.configFile =  {
    "nvim/lazy-lock.json".source = (config.lib.file.mkOutOfStoreSymlink 
      "${config.home.homeDirectory}/nixfiles/home-manager/programs/neovim/lazy-lock.json"
    );
    # "nvim/lazy-lock.json".enable = false;
    "nvim/".source ="${inputs.dotfiles}/xdg-config/.config/nvim/";
    "nvim/".recursive = true;

  };
  home.packages = with pkgs; [
    neovim-remote
  ];
  programs.neovim = {
    enable = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    extraPackages = with pkgs; [
      gcc
      isort
      lua-language-server
      nixd
      prettierd
      ruff
      rust-analyzer-unwrapped
      ripgrep
      ruff
      rust-analyzer-unwrapped
    ];
  };
}
