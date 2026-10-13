# Single-disk layout: an ESP plus one LUKS partition holding btrfs subvolumes.
#
# The passphrase is only read while formatting, from `passwordFile`. It is a
# string on purpose: a path literal (./disk.key) would copy the passphrase into
# the world-readable Nix store. At boot it is typed in, at the console or over
# SSH into the initrd (see modules/initrd-ssh-unlock.nix), so nothing on the
# machine stores it.
#
# Each `content` is the next layer down (gpt > luks > btrfs); the types and
# their options: https://github.com/nix-community/disko/tree/master/lib/types
# See also https://wiki.nixos.org/wiki/Remote_disk_unlocking and
# https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#LUKS_on_a_partition
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
        # https://wiki.archlinux.org/title/EFI_system_partition
        ESP = {
          size = espSize;
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            # Root-only: the initrd on it holds the initrd's SSH host key.
            mountOptions = [ "umask=0077" ];
          };
        };
        # The rest of the disk; "100%" partitions are created last (`priority`
        # in https://github.com/nix-community/disko/blob/master/lib/types/gpt.nix).
        luks = {
          size = "100%";
          content = {
            # https://github.com/nix-community/disko/blob/master/lib/types/luks.nix
            type = "luks";
            # Unlocked volume appears as /dev/mapper/cryptroot; any name works.
            name = "cryptroot";
            inherit passwordFile;
            # https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              # mkfs.btrfs -f: overwrite any existing filesystem signature.
              extraArgs = [ "-f" ];
              # Keys are subvolume paths inside btrfs, not mountpoints:
              # https://btrfs.readthedocs.io/en/latest/Subvolumes.html
              subvolumes =
                let
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                in
                {
                  "/rootfs" = {
                    mountpoint = "/";
                    inherit mountOptions;
                  };
                  "/home" = {
                    mountpoint = "/home";
                    inherit mountOptions;
                  };
                  # Kept out of snapshots of / and /home.
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
