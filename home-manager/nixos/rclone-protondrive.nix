{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.services.rclone-protondrive;
  mountdir = config.home.homeDirectory + "/Proton";
in
{
  # Off by default: this module was dead code until the nixos/ auto-import was
  # fixed, so no Linux host has ever actually run the mount. Opt in per host.
  options.services.rclone-protondrive.enable =
    lib.mkEnableOption "rclone ProtonDrive mount at ~/Proton";

  config = lib.mkIf cfg.enable {
    systemd.user.services.rclone-protondrive = {
      Unit = {
        Description = "mount protondrive dirs";
        After = [ "network-online.target" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mountdir}";
        ExecStart = ''
          ${pkgs.rclone}/bin/rclone mount proton: ${mountdir} \
              --dir-cache-time 48h \
              --vfs-cache-mode full \
              --vfs-cache-max-age 48h \
              --vfs-read-chunk-size 10M \
              --vfs-read-chunk-size-limit 512M \
              --buffer-size 512M
        '';
        # fusermount must be the host's setuid wrapper: /run/wrappers/bin on
        # NixOS, /usr/bin on Nobara/Fedora. Resolved via the unit PATH below
        # (systemd >= 239 looks up non-absolute Exec binaries in $PATH).
        ExecStop = "fusermount -u ${mountdir}";
        Type = "notify";
        Restart = "always";
        RestartSec = "10s";
        Environment = [ "PATH=/run/wrappers/bin:/usr/bin:${pkgs.fuse}/bin" ];
      };
    };
  };
}
