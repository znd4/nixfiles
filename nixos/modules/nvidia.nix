
{ inputs, hostname, config, ... }:
let
  enabled = builtins.elem hostname [
    "desktop"
  ];
in
if !enabled then {} else
{
  # Copied from nixos.wiki/wiki/Nvidia
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;

    # Might need to enable this if I have issues sleeping
    powerManagement.enable = true;

    # If I ever have a laptop with nvidia dGPU, might want
    # to revisit this
    powerManagement.finegrained = false;

    # Don't use open-source nvidia driver
    open = false;

    # Get `nvidia-settings` command
    nvidiaSettings = true;

    # package = config.boot.kernelPackages.nvidiaPackages.stable;
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };
}
