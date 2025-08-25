{ inputs, system, ... }:
#./pre-commit-cert-overlay.nix
final: prev: {
  # Override the pre-commit package to include pip-system-certs
  pre-commit = inputs.pre-commit.legacyPackages.${system}.pre-commit;
}
