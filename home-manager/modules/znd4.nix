# Per-host knobs for this configuration. A host sets these in its module list
# (see `homeConfigurations` in flake.nix) instead of passing factory arguments.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.znd4;
in
{
  options.znd4 = {
    certificateAuthorities = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra certificate authorities, as PEM text, to trust on top of the
        Mozilla bundle from `pkgs.cacert`. When this is not empty, git, Node,
        Python requests and OpenSSL use
        {option}`znd4.certificateAuthorityBundle`.
      '';
    };
    certificateAuthorityBundle = mkOption {
      type = types.nullOr types.str;
      readOnly = true;
      description = ''
        Path of a CA bundle: `pkgs.cacert` followed by
        {option}`znd4.certificateAuthorities`. `null` when no extra
        authorities are set. Derived; do not set.
      '';
    };

    sesh = {
      gitlabHosts = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "gitlab.example.com" ];
        description = "GitLab hosts that the clone-pick repo picker (tmux M-m, herdr alt+m) lists projects from.";
      };
      githubOrgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "znd4" ];
        description = "GitHub organizations that the clone-pick repo picker lists repositories from.";
      };
    };
  };

  config.znd4.certificateAuthorityBundle =
    if cfg.certificateAuthorities == [ ] then
      null
    else
      "${pkgs.concatTextFile {
        name = "ca-bundle-combined";
        files = [
          "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          (builtins.toFile "custom-ca.pem" (lib.concatStringsSep "\n" cfg.certificateAuthorities))
        ];
      }}";
}
