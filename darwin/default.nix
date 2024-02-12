{pkgs, username, ...}: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
  };
  nix.package = pkgs.nix;
  programs.fish.enable = true;
}
