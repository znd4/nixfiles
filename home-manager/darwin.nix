

{ inputs, username, stateVersion }:
{ lib, config, pkgs, ... }: {
  # You can import other home-manager modules here
  _module.args = {
    inherit inputs;
    inherit username;
    inherit stateVersion;
    # inherit pkgs;
    system = "aarch64-darwin";
  };
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    ./shared.nix
    ./programs/kmonad.nix
  ];
  home.file.".1password/agent.sock".source = config.lib.file.mkOutOfStoreSymlink
    "/Users/${username}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  home.sessionPath = [ "/Users/${username}/homebrew/bin" ];
  home.packages = with pkgs; [ python311Packages.supervisor ];
  home.stateVersion = stateVersion;
}
