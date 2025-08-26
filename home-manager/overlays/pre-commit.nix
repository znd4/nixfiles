{ ... }:
#./pre-commit-cert-overlay.nix
final: prev: {
  # Override pre-commit to use our uv-based wrapper with system certs
  pre-commit = prev.callPackage ../pkgs/pre-commit-system-certs.nix { };
}
