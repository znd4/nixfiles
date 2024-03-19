{
  pkgs,
  hostname,
  username,
  ...
}:
if !(builtins.elem hostname ["desktop"])
then {}
else {
  users.users.${username}.packages = with pkgs; [
    # nix run nixpkgs#steamcmd
    steam-tui
  ];

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };
}
