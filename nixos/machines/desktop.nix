# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{
  config,
  lib,
  outputs,
  username,
  modulesPath,
  ...
}: {
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      AllowUsers = [username];
    };
  };
  users.users.${username}.openssh.authorizedKeys.keys = [outputs.keys.Desktop];

  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  boot.initrd.luks.devices."luks-f380fed3-c5d0-4257-b880-15362768a758".device = "/dev/disk/by-uuid/f380fed3-c5d0-4257-b880-15362768a758";

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/c490e6ae-375c-458e-be63-f423f27475e9";
    fsType = "ext4";
  };

  boot.initrd.luks.devices."luks-bdf10f66-fd6d-446d-9966-08b105745d1d".device = "/dev/disk/by-uuid/bdf10f66-fd6d-446d-9966-08b105745d1d";

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/592B-AEE2";
    fsType = "vfat";
  };

  swapDevices = [{device = "/dev/disk/by-uuid/aba13537-f387-40ec-a134-15dc2c806a9f";}];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp4s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlo1.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
