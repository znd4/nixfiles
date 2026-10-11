# Unlock LUKS over SSH: the systemd initrd brings up DHCP and an sshd whose
# root shell is the password agent, so `ssh -p 2222 root@host` drops straight
# into the passphrase prompt and boot continues once it is answered.
{ config, lib, ... }:
let
  cfg = config.znd4.initrdSshUnlock;
in
{
  options.znd4.initrdSshUnlock = {
    enable = lib.mkEnableOption "unlocking LUKS over SSH from the initrd";

    # Not 22, so the initrd's host key never collides with the real system's
    # in known_hosts.
    port = lib.mkOption {
      type = lib.types.port;
      default = 2222;
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    authorizedKeyFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };

    # A string, not a path: the private key is read from the installed system
    # when the bootloader is written and appended to the initrd, never copied
    # into the Nix store. It lives on the unencrypted ESP, so it must not be the
    # system's main host key.
    hostKey = lib.mkOption {
      type = lib.types.str;
      default = "/etc/secrets/initrd/ssh_host_ed25519_key";
    };

    # Kernel modules for the NIC; the initrd only has what is listed here.
    networkModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "r8169" ];
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.availableKernelModules = cfg.networkModules;
    boot.initrd.systemd = {
      enable = true;
      users.root.shell = "/bin/systemd-tty-ask-password-agent";
      network = {
        enable = true;
        networks."10-initrd-ssh" = {
          matchConfig.Name = "en* eth*";
          networkConfig.DHCP = "yes";
        };
      };
    };
    boot.initrd.network = {
      enable = true;
      ssh = {
        enable = true;
        inherit (cfg) port authorizedKeys authorizedKeyFiles;
        hostKeys = [ cfg.hostKey ];
      };
    };
  };
}
