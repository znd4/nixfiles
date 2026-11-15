{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.znd4.steam.enable = lib.mkEnableOption "Steam, with Remote Play and dedicated-server ports open";

  config = lib.mkIf config.znd4.steam.enable {
    users.users.${config.znd4.username}.packages = with pkgs; [
      # nix run nixpkgs#steamcmd
      steam-tui
    ];

    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    };
  };
}
