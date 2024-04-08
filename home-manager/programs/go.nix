{ pkgs, ... }:
{

  programs.go = {
    enable = true;
    goPath = "go";
    goBin = ".local/bin.go";
  };
  home.packages = with pkgs; [ gotools ];
}
