{
  pkgs,
  config,
  options,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.programs.op-gh;
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
            final.jq
            prev.gh
          ];
          text = ''
            if [ -t 0 ]; then
              exec op plugin run -- gh "$@"
            fi
            # Without a TTY (Claude Code, scripts, cron) `op plugin run` fails
            # with "interactive IO not available", but `op read` can still
            # authorize through the desktop app. Reuse the credential the
            # plugin was configured with (`op plugin init gh`).
            used_items="''${XDG_CONFIG_HOME:-$HOME/.config}/op/plugins/used_items/gh.json"
            if [ -r "$used_items" ]; then
              ref=$(jq -r '.[0] | "op://\(.vault_id)/\(.item_id)/token"' "$used_items")
              GH_TOKEN=$(op read "$ref") exec gh "$@"
            fi
            exec gh "$@"
          '';
        };
      })
    ];
    home.packages = with pkgs; [ gh ];
  };
}
