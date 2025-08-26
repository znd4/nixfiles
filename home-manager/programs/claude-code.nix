{
  pkgs,
  config,
  options,
  lib,
  inputs,
  system,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.programs.claude-code;
in
{
  options.programs.claude-code = {
    enable = lib.mkOption {
      default = true;
      example = true;
      description = "Whether to install claude-code with extra packages";
      type = lib.types.bool;
    };
    package =
      lib.mkPackageOption
        (import inputs.nixpkgs-unstable {
          inherit system;
          config = {
            allowUnfree = true;
            allowUnfreePredicate = _: true;
          };
        })
        "claude-code"
        {
          default = "claude-code";
        };
    extraPackages = lib.mkOption {
      default = [ ];
      example = [ pkgs.mcp-grafana ];
      description = "Extra packages to make available to your claude-code path (e.g. MCP servers)";
      type = lib.types.listOf lib.types.package;
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ] ++ cfg.extraPackages;
  };
}
