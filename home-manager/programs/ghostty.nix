{
  pkgs,
  inputs,
  lib,
  ...
}:
let
  ghosttyFlakePackage = inputs.ghostty.packages.${pkgs.stdenv.system}.ghostty;
  ghosttyPkg =
    if (builtins.elem pkgs.stdenv.system ghosttyFlakePackage.meta.platforms) then
      ghosttyFlakePackage
    else
      pkgs.emptyDirectory;
in
{
  home.packages = lib.mkIf pkgs.stdenv.isLinux [
    inputs.ghostty.packages.${pkgs.stdenv.system}.ghostty
  ];
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    package = ghosttyPkg;
    settings = {
      window-theme = "dark";
      theme = "tokyonight-storm";
      shell-integration-features = "no-cursor";
      font-family = "MonaspiceAr Nerd Font Mono";
      macos-titlebar-style = "hidden";
      font-style = "Medium";
      font-family-italic = "MonaspiceRn Nerd Font Mono";
      font-style-italic = "Italic";
    };
  };
}
