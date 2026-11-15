{ inputs, ... }:
{
  imports = [
    ./git-hooks.nix
    ./packages
  ];
}
