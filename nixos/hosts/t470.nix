# ThinkPad T470.
{
  imports = [ ../machines/t470.nix ];

  networking.hostName = "t470";
  znd4.username = "znd4";

  system.stateVersion = "23.11"; # Did you read the comment in ../default.nix?
}
