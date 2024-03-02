{ pkgs, inputs, config, username, ... }:
{

  xdg.configFile = let
    nvSource = "${inputs.dotfiles}/xdg-config/.config/nvim";
    nixfiles = config."${username}".nixfiles;
  in {
    "nvim/lazy-lock.json".source = (config.lib.file.mkOutOfStoreSymlink 
      "${config.home.homeDirectory}/nixfiles/home-manager/programs/neovim/lazy-lock.json"
    );
    "nvim/".source = "${nvSource}/";

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
