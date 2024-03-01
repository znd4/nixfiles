# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.luks.devices."luks-2a3d8835-b168-4890-b176-31ffcaa2477f".device = "/dev/disk/by-uuid/2a3d8835-b168-4890-b176-31ffcaa2477f";
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/3a568332-dbef-46cb-a033-7ac6ac4ababd";
    fsType = "ext4";
  };

  boot.initrd.luks.devices."luks-e4cec459-f79b-4aba-89da-d674767fdbde".device = "/dev/disk/by-uuid/e4cec459-f79b-4aba-89da-d674767fdbde";

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/DC2E-553A";
    fsType = "vfat";
  };

  swapDevices = [ { device = "/dev/disk/by-uuid/a50fd497-9277-40f6-bb71-b94e5a75496d"; } ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp0s31f6.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp4s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
