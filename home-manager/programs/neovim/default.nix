{
  pkgs,
  system,
  inputs,
  lib,
  config,
  username,
  ...
}:
let
  neovim_python = pkgs.python3.withPackages (
    ps: with ps; [
      pynvim
      debugpy
    ]
  );
  tofu-ls = inputs.nixos-unstable.legacyPackages.${system}.tofu-ls;
in
{
  xdg.configFile = {
    "nvim/lazy-lock.json".source = (
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/home-manager/programs/neovim/lazy-lock.json"
    );
    # "nvim/lazy-lock.json".enable = false;
    "nvim/".source = "${inputs.self}/xdg-config/nvim/";
    "nvim/".recursive = true;
  };
  home.sessionVariables = {
    NVIM_PYTHON = "${neovim_python}/bin/python";
  };
  nixpkgs.overlays = [ inputs.nixd.overlays.default ];
  home.packages = with pkgs; [ neovim-remote ];
  programs.neovim = {
    enable = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    extraLuaPackages = ps: with ps; [ jsregexp ];
    extraPackages =
      with pkgs;
      [
        basedpyright
        dprint
        gcc
        glow
        helm-ls
        jsonnet-language-server
        lua-language-server
        marksman
        neovim-remote
        nil
        nixd
        nixfmt-rfc-style
        nodePackages.vscode-json-languageserver
        prettierd
        ruff
        rust-analyzer-unwrapped
        taplo
        tofu-ls
        typescript-language-server
        tree-sitter
        yaml-language-server
      ]
      ++ {
        aarch64-darwin = [ ];
        x86_64-linux = with pkgs; [ plocate ];
      }
      .${system};
  };
}
