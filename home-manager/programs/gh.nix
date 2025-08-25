{
  pkgs,
  config,
  options,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.programs.okta-aws-cli-assume-role;
in
{
  options.programs.op-gh = {
    enable = lib.mkOption {
      default = true;
      example = true;
      description = "Whether to install a `gh` script that wraps the actual `gh` CLI with 1password plugin authentication";
      type = lib.types.bool;
    };
  };
  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      (final: prev: {
        gh = final.writeShellApplication {
          name = "gh";
          runtimeInputs = [
            final._1password-cli
            prev.gh
          ];
          text = ''
            #!${final.runtimeShell}
            # 'exec' replaces the shell process with the 'op' process, which is
            # more efficient and handles signals correctly.
            # "$@" forwards all arguments, preserving spaces and special characters.
            exec op plugin run -- gh "$@"
          '';
        };
      })
    ];
    home.packages = with pkgs; [ gh ];
  };
}
