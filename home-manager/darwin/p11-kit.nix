{ ... }:
{
  # The overlay must be unconditional (pkgs depends on nixpkgs.overlays), so
  # it checks the platform itself and leaves p11-kit alone elsewhere.
  nixpkgs.overlays = [
    (final: prev: {
      p11-kit =
        if prev.stdenv.isDarwin then
          prev.p11-kit.overrideAttrs (oldAttrs: {
            mesonCheckFlags = [
              "--timeout-multiplier"
              "0"
            ];
          })
        else
          prev.p11-kit;
    })
  ];
}
