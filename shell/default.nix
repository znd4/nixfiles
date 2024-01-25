{ lib, config, pkgs, ... }: {

  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [ tmux-thumbs pain-control sensible catppuccin ];
  };
  programs.fish.enable = lib.mkDefault true;
}
