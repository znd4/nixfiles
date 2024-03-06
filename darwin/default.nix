{
  pkgs,
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
  fonts.fonts = with pkgs; [
    (nerdfonts.override {
      fonts = [
        "FiraCode"
        "VictorMono"
      ];
    })
  ];
  nix.settings.experimental-features = "nix-command flakes";

  system.stateVersion = stateVersion;

  services.nix-daemon.enable = true;

  environment.systemPackages = with pkgs; [ inputs.home-manager.packages.${system}.default ];

  programs.fish.enable = true;
  programs.zsh.enable = true;

  homebrew = {
    brewPrefix = "/Users/${username}/homebrew/bin";
    enable = true;
    casks = [ "1password-cli" ];
  };
  # environment.postBuild 
}
