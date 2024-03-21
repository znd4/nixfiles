{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [inputs.home-manager.packages.${system}.default];
}
