{ pkgs, ... }:
{
  # op on PATH for every host, including non-NixOS ones (Nobara desktop)
  # where nixos/modules/1password.nix doesn't apply.
  home.packages = [ pkgs._1password-cli ];
}
