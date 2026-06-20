# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  pkgs,
  keys,
  certificateAuthority,
  lib,
  ...
}:
let
  system = pkgs.stdenv.system;
in
{
  imports = [
    inputs.hunkdiff.homeManagerModules.default
  ];
  programs.hunk = {
    enable = true;
    settings = { };
    enableGitIntegration = true;
  };
}
