{ inputs, ... }:
{
  programs.wezterm = {
    enable = true;
    extraConfig = builtins.readFile "${inputs.self}/dotfiles/xdg-config/.config/wezterm/wezterm.lua";
  };
}
