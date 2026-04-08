{ pkgs, ... }:
{

  programs.go = {
    enable = true;
  };
  home.packages = with pkgs; [
    gotools
    golangci-lint
    gofumpt
    gopls
  ];
}
