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
  pluginConfig = pkgs.writeText "op-plugin-gh.json" (
    builtins.toJSON {
      account_id = cfg.credential.accountId;
      entrypoint = [ "gh" ];
      credentials = [
        {
          plugin = "github";
          credential_type = "personal_access_token";
          vault_id = cfg.credential.vaultId;
          item_id = cfg.credential.itemId;
        }
      ];
    }
  );
in
{
  options.programs.op-gh = {
    enable = lib.mkOption {
      default = true;
      example = true;
      description = "Whether to install a `gh` script that wraps the actual `gh` CLI with 1password plugin authentication";
      type = lib.types.bool;
    };
    credential = lib.mkOption {
      default = null;
      description = ''
        The 1Password item that `op plugin run -- gh` authenticates with. When
        set, it is written to ~/.config/op/plugins/gh.json as the global
        default, the same file `op plugin init gh` writes. When null, every
        `gh` call asks which item to use.
      '';
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            accountId = lib.mkOption { type = lib.types.str; };
            vaultId = lib.mkOption { type = lib.types.str; };
            itemId = lib.mkOption { type = lib.types.str; };
          };
        }
      );
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

    # op ignores a plugin config that is a symlink or is not mode 600, so
    # home.file cannot provide it. Copy it into place instead.
    home.activation.opGhPluginDefault = mkIf (cfg.credential != null) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p -m 700 "${config.xdg.configHome}/op/plugins"
        run install -m 600 ${pluginConfig} "${config.xdg.configHome}/op/plugins/gh.json"
      ''
    );
  };
}
