{
  inputs,
  hostname,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [ via ];
  hardware.keyboard.qmk.enable = true;
  services.udev.packages = [ pkgs.via ];
}
