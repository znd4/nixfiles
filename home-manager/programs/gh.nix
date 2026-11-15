{
  inputs,
  pkgs,
  config,
  options,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.programs.op-gh;
  # gh from its own pin (see `nixpkgs-gh` in flake.nix): `gh skill` needs 2.90+.
  gh = inputs.nixpkgs-gh.legacyPackages.${pkgs.stdenv.hostPlatform.system}.gh;
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
  # One overlay sets both the version and the 1Password wrapper. With two, the
  # order in which modules define nixpkgs.overlays would decide which one wins.
  config = {
    nixpkgs.overlays = [
      (final: prev: {
        gh =
          if cfg.enable then
            final.writeShellApplication {
              name = "gh";
              runtimeInputs = [
                final._1password-cli
                gh
              ];
              text = ''
                #!${final.runtimeShell}
                # 'exec' replaces the shell process with the 'op' process, which is
                # more efficient and handles signals correctly.
                # "$@" forwards all arguments, preserving spaces and special characters.
                exec op plugin run -- gh "$@"
              '';
            }
          else
            gh;
      })
    ];
    home.packages = mkIf cfg.enable [ pkgs.gh ];
  };
}
