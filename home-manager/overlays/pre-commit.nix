{ ... }:
#./pre-commit-cert-overlay.nix
final: prev: {
  # Override the pre-commit package to include pip-system-certs
  pre-commit = prev.pre-commit.overrideAttrs (oldAttrs: {
    # Add pip-system-certs to the propagated build inputs
    buildInputs = oldAttrs.builtInputs ++ [
      prev.python3Packages.pip-system-certs
    ];
  });
}
