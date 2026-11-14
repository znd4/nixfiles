# Per-host knobs for this configuration. A host sets these in its module list
# (see `homeConfigurations` in flake.nix) instead of passing factory arguments.
{
  config,
  inputs,
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
    hostname = mkOption {
      type = types.str;
      example = "desktop";
      description = ''
        Name of the machine this configuration is for, as in the
        `homeConfigurations."<user>@<hostname>"` attribute. It selects the
        host's entry in the flake's `keys`. To change behavior per machine,
        add an option that names the capability (see `znd4.ssh.agent`)
        rather than testing this value.
      '';
    };
    keys = mkOption {
      type = types.attrsOf types.str;
      description = ''
        SSH public keys by host name. Each key becomes an `IdentityFile`
        match block in the SSH config; `github.com` is also the git signing
        key. Each entry of `defaultKeys` in flake.nix is set with
        `mkDefault`, and each entry of `keys.''${hostname}` with priority
        900, so a host can add or override single entries.
      '';
    };
    knownHosts = mkOption {
      type = types.attrsOf types.lines;
      description = ''
        `known_hosts` lines, grouped by host name. The SSH config uses them
        as its `UserKnownHostsFile`. Each entry of `knownHosts` in flake.nix
        is set with `mkDefault`.
      '';
    };
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

  config.znd4.keys =
    lib.mapAttrs (_: lib.mkDefault) inputs.self.defaultKeys
    // lib.mapAttrs (_: lib.mkOverride 900) (inputs.self.keys.${cfg.hostname} or { });
  config.znd4.knownHosts = lib.mapAttrs (_: lib.mkDefault) inputs.self.knownHosts;

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
