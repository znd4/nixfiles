{
  pkgs,
  inputs,
  lib,
  ...
}:
{
  home.packages = lib.mkIf pkgs.stdenv.isLinux [
    inputs.ghostty.packages.${pkgs.stdenv.system}.ghostty
  ];
  programs.ghostty = {
    enable = true;
    shellIntegration = {
      enable = true;
    };
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
