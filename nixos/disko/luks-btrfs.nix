# Single-disk layout: an ESP plus one LUKS partition holding btrfs subvolumes.
#
# The passphrase is only read while formatting, from `passwordFile`. It is a
# string on purpose: a path literal (./disk.key) would copy the passphrase into
# the world-readable Nix store. At boot it is typed in, at the console or over
# SSH into the initrd (see modules/initrd-ssh-unlock.nix), so nothing on the
# machine stores it.
{
  device,
  passwordFile ? "/tmp/disk.key",
  espSize ? "1G",
}:
{
  disko.devices.disk.main = {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = espSize;
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            inherit passwordFile;
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes =
                let
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                in
                {
                  "/root" = {
                    mountpoint = "/";
                    inherit mountOptions;
                  };
                  "/home" = {
                    mountpoint = "/home";
                    inherit mountOptions;
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    inherit mountOptions;
                  };
                };
            };
          };
        };
      };
    };
  };
}
