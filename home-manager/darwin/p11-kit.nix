
{ pkgs, inputs, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      p11-kit = prev.p11-kit.overrideAttrs (oldAttrs: {
        mesonCheckFlags = [ "--timeout-multiplier" "0" ];
      });
    })
  ];
}
