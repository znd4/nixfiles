{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
{

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withPython3 = true;
    withNodeJs = true;
  };

  environment.systemPackages = with pkgs; [ inputs.home-manager.packages.${system}.default ];
}
