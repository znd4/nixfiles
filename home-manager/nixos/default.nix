{
  keys,
  username,
  pkgs,
  lib,
  system,
  ...
}:
if !(lib.strings.hasSuffix "linux" system)
then {}
else {
  # You can import other home-manager modules here
  imports =
    [
      # If you want to use modules your own flake exports (from modules/home-manager):
      # outputs.homeManagerModules.example

      # Or modules exported from other flakes (such as nix-colors):
      # inputs.nix-colors.homeManagerModules.default

      # You can also split up your configuration and import pieces of it here:
    ]
    # ++ (
    #   builtins.map
    #   (
    #     f:
    #       (import (./.+ "/${f}"))
    #       (
    #         builtins.filter
    #         (f: f != "default.nix")
    #         (builtins.attrNames (builtins.readDir ./.))
    #       )
    #   )
    # )
    ;

  home.homeDirectory = "/home/" + username;
  home.sessionVariables.SSH_AUTH_SOCK = "/home/${username}/.1password/agent.sock";
  home.packages = with pkgs; [
    _1password
    #appimageTools
    logseq

    appimage-run
    mpv-unwrapped
    rpi-imager
    signal-desktop
  ];
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
}
