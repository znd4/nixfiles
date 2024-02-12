{pkgs, username, ...}: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
  };
  services.nix-daemon.enable = true;
}
