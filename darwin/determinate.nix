# For Macs where Nix was installed with the Determinate installer.
# nix-darwin refuses to activate while it manages Nix alongside
# determinate-nixd, so turn that off. The nix.settings in ./default.nix are
# ignored when nix.enable = false, so repeat them in nix.custom.conf, the file
# Determinate's nix.conf includes for user settings.
{ ... }:
{
  nix.enable = false;

  environment.etc."nix/nix.custom.conf".text = ''
    extra-experimental-features = ca-derivations
    extra-substituters = https://nix-community.cachix.org
    extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
    extra-platforms = aarch64-linux x86_64-linux
  '';
}
