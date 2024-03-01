{ pkgs, inputs, config, ... }:
{

  xdg.configFile = let
    nvSource = "${inputs.dotfiles}/xdg-config/.config/nvim";
  in {
    "nvim/".source = "${nvSource}/";
    # "nvim/lazy-lock.json".source = config.lib.file.mkOutOfStoreSymlink "${config.my.configDir}/home-manager/programs/neovim/lazy-lock.json";
    # "nvim/lua".source = "${nvSource}/lua";
    # "nvim/after".source = "${nvSource}/after";
    # "nvim/queries".source = "${nvSource}/queries";
    # "nvim/syntax".source = "${nvSource}/syntax";
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
      fd
      lua-language-server
      ruff
      rust-analyzer-unwrapped
      ripgrep
      ruff
      rust-analyzer-unwrapped
    ];
  };
}
