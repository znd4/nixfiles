{pkgs, username, ...}: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
  };
  nix.package = pkgs.nix;
  programs.fish.enable = true;
}
