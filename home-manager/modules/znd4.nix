# Per-host knobs for this configuration. A host sets these in its module list
# (see `homeConfigurations` in flake.nix) instead of passing factory arguments.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.znd4 = {
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
}
