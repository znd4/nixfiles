{ pkgs, lib, inputs, username, ... }: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
  };
  nix.settings.experimental-features = "nix-command flakes";
  services.nix-daemon.enable = true;
  homebrew = {
    brewPrefix = "/Users/${username}/homebrew/bin";
    enable = true;
    brews = [ "1password-cli" ];
  };
  # environment.postBuild 
}
