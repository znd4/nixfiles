{ ... }:
#./pre-commit-cert-overlay.nix
final: prev: {
  # Override the pre-commit package to include pip-system-certs
  pre-commit = prev.pre-commit.overrideAttrs (oldAttrs: {
    # Add pip-system-certs to the propagated build inputs
    dependencies = oldAttrs.dependencies ++ [
      prev.python3Packages.pip-system-certs
    ];
  });
}
