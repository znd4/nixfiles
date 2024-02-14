

{ inputs, username, stateVersion }:
{ lib, config, pkgs, ... }: {
  # You can import other home-manager modules here
  _module.args = {
    inherit inputs;
    inherit username;
    inherit stateVersion;
  };
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    (args:
      (import ./shared.nix) (args // {
        inherit inputs;
        inherit username;
        inherit stateVersion;
        inherit pkgs;
      }))
    ./programs/kmonad.nix
  ];
  home.packages = with pkgs; [ python311Packages.supervisor ];
  home.stateVersion = stateVersion;
}
