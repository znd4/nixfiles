{
  config,
  pkgs,
  lib,
  ...
}:
# Obsidian Sync without the desktop app. Obsidian says not to run headless
# sync and the desktop app's Sync on the same device, so before enabling the
# service, turn off Settings > Core plugins > Sync in the desktop app on this
# machine. The app can stay installed as an editor.
#
# One-time setup, run by hand (it prompts for the password, MFA code and the
# vault's encryption password):
#   ob login
#   ob sync-setup --vault <name> --path <vaultPath> --device-name <host>-headless
#   ob sync --path <vaultPath>          # first sync in the foreground
# The token is stored in ~/.obsidian-headless/auth_token (on Linux,
# $XDG_CONFIG_HOME/obsidian-headless).
let
  cfg = config.programs.obsidian-headless;
  ob = import ../../pkgs/obsidian-headless { inherit pkgs; };
  syncArgs = [
    "${ob}/bin/ob"
    "sync"
    "--continuous"
    "--path"
    cfg.vaultPath
  ];
in
{
  options.programs.obsidian-headless = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the obsidian-headless CLI (ob).";
    };

    service.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run `ob sync --continuous` for vaultPath as a launchd agent (macOS) or
        systemd user service (Linux). Enable only after the one-time setup
        above, and after Sync is off in the desktop app on this machine.
      '';
    };

    vaultPath = lib.mkOption {
      type = lib.types.str;
      default = config.programs.zk.settings.notebook.dir;
      defaultText = lib.literalExpression "config.programs.zk.settings.notebook.dir";
      description = "Local vault that the service syncs.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { home.packages = [ ob ]; }

      (lib.mkIf (cfg.service.enable && pkgs.stdenv.isDarwin) {
        launchd.agents.obsidian-headless = {
          enable = true;
          config = {
            ProgramArguments = syncArgs;
            RunAtLoad = true;
            # Restart after a crash or a dropped connection, not after a clean exit.
            KeepAlive.SuccessfulExit = false;
            ThrottleInterval = 30;
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/obsidian-headless.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/obsidian-headless.log";
            ProcessType = "Background";
          };
        };
      })

      (lib.mkIf (cfg.service.enable && pkgs.stdenv.isLinux) {
        systemd.user.services.obsidian-headless = {
          Unit = {
            Description = "Obsidian headless sync";
            After = [ "network-online.target" ];
          };
          Install.WantedBy = [ "default.target" ];
          Service = {
            ExecStart = lib.escapeShellArgs syncArgs;
            Restart = "on-failure";
            RestartSec = 30;
          };
        };
      })
    ]
  );
}
