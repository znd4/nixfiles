{ pkgs, ... }:
{
  home.packages = with pkgs; [
    texliveMinimal
    texlab
  ];
}
