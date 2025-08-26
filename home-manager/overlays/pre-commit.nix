{ outputs, system, ... }:
#./pre-commit-cert-overlay.nix
final: prev: {
  # Override pre-commit to use our uv-based wrapper with system certs
  pre-commit = outputs.packages.${system}.pre-commit-system-certs;
}
