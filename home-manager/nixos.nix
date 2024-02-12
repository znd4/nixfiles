
{ inputs, username, lib, config, pkgs, stateVersion, ... }: {
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    ./shared.nix
  ];
  # TODO: Set your username
  home.homeDirectory = "/home/" + username;
  home.packages = with pkgs; [
      appimage-run
  ];
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
}
