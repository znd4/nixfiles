{
  inputs,
  hostname,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    via
    qmk
  ];
  hardware.keyboard.qmk.enable = true;
  services.udev.packages = [ pkgs.via ];
}
