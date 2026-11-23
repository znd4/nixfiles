{ pkgs, ... }:
{
  programs.kubeswitch = {
    enable = true;
    # Upstream fix bdd6809c (not in 0.9.3, the nixpkgs version): drop the cluster CA for the GKE DNS endpoint.
    # Without it, kubectl fails with "x509: certificate signed by unknown authority".
    package = pkgs.kubeswitch.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./gke-dns-endpoint-ca.patch ];
    });
  };
}
