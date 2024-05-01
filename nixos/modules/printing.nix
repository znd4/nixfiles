{ pkgs, ... }:
{
  # Enable CUPS to print documents.
  services.printing.enable = true;
  environment.systemPackages = with pkgs; [ brlaser ];
}
