{pkgs, username, ...}: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
  };
  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;
  programs.fish.enable = true;

}
