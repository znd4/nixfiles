{ inputs, ... }:
{
  programs.wezterm = {
    enable = true;
    extraConfig = builtins.readFile "${inputs.dotfiles}/xdg-config/.config/wezterm/wezterm.lua";
  };
}
