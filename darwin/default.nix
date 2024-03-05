{
  pkgs,
  lib,
  inputs,
  username,
  system,
  stateVersion,
  ...
}:
{
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
  };
  # TODO: add fonts.fonts
  # fonts.fonts = with pkgs; [];
  nix.settings.experimental-features = "nix-command flakes";

  services.nix-daemon.enable = true;

  environment.systemPackages = with pkgs; [ inputs.home-manager.packages.${system}.default ];
  environment.variables = {
    SSH_ASKPASS = "ssh-askpass";
  };

  programs.fish.enable = true;
  programs.zsh.enable = true;
  targets.darwin.default = {
    # https://macos-defaults.com/#%F0%9F%92%BB-list-of-commands
    "com.apple.finder" = {
      AppleShowAllFiles = true;
    };
  };

  homebrew = {
    brewPrefix = "/Users/${username}/homebrew/bin";
    enable = true;
    casks = [ "1password-cli" ];
  };
  # environment.postBuild 
}
