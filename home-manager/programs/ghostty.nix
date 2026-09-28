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
      null;
in
{
  home.packages = lib.mkIf pkgs.stdenv.isLinux [
    inputs.ghostty.packages.${pkgs.stdenv.system}.ghostty
  ];
  xdg.configFile."ghostty/themes/catppuccin-macchiato.conf" = {
    source = "${inputs.catppuccin-ghostty}/themes/catppuccin-macchiato.conf";
  };
  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    package = ghosttyPkg;
    settings = {
      window-theme = "dark";
      theme = "catppuccin-macchiato.conf";
      shell-integration-features = "no-cursor";
      command = "${pkgs.fish}/bin/fish";
      desktop-notifications = true;
      font-family = "MonaspiceAr Nerd Font Mono";
      macos-titlebar-style = "hidden";
      macos-option-as-alt = true;
      font-style = "Medium";
      font-family-italic = "MonaspiceRn Nerd Font Mono";
      font-style-italic = "Italic";
    }
    # On a terminal bell (BEL), play a soft sound and mark the window. tmux
    # sends bells from all panes to Ghostty, so you hear an agent in a hidden pane.
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      bell-features = "audio,attention,title";
      bell-audio-path = "/System/Library/Sounds/Glass.aiff";
      bell-audio-volume = 0.4;
    };
  };
}
