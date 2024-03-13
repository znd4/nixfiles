{ pkgs, ... }:
{
  home.packages = with pkgs; [ hydroxide ];
  # systemd.user.services.hydroxide = {
  #   Unit = {
  #     Description = "Open source protonmail bridge server";
  #   };
  # };
}
