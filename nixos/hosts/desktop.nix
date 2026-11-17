# Desktop gaming PC.
{
  imports = [ ../machines/desktop.nix ];

  networking.hostName = "desktop";
  znd4.username = "znd4";
  znd4.nvidia.enable = true;
  znd4.steam.enable = true;

  system.stateVersion = "23.11"; # Did you read the comment in ../default.nix?
}
