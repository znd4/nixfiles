{ lib, config, pkgs, ... }: {

  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [ tmux-thumbs pain-control sensible catppuccin ];
  };
  programs.fish.enable = lib.mkDefault true;
  programs.starship.enable = true;
  environment.systemPackages = with pkgs; [
    gh
    git
  ];
}
