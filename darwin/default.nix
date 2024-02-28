{ pkgs, lib, inputs, username, stateVersion, ... }: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
  };
  # TODO: add fonts.fonts
  # fonts.fonts = with pkgs; [];
  system.stateVersion = stateVersion;
  nix.settings.experimental-features = "nix-command flakes";

  services.nix-daemon.enable = true;

  environment.variables = { SSH_ASKPASS = "ssh-askpass"; };

  programs.fish.enable = true;
  programs.zsh.enable = true;

  homebrew = {
    brewPrefix = "/Users/${username}/homebrew/bin";
    enable = true;
    casks = [ "1password-cli" ];
    brews = [{
      name = "theseal/ssh-askpass/ssh-askpass";
      start_service = true;
    }];
  };
  # environment.postBuild 
}
