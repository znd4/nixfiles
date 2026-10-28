# cloudlens — a k9s-style TUI for AWS and GCP (github.com/one2nc/cloudlens).
# nixpkgs already packages the latest release, so there is no pkgs/ entry.
# It has no config file of its own: it reads ~/.aws/config, and GCP takes a
# credentials file on the command line (`cloudlens gcp --cf=...`).
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.cloudlens;
in
{
  options.programs.cloudlens = {
    enable = lib.mkEnableOption "cloudlens, a k9s-like TUI for AWS and GCP";
    package = lib.mkPackageOption pkgs "cloudlens" { };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
