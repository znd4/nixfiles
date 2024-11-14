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
    shell = "${pkgs.fish}/bin/fish";
    isHidden = false;
  };
  fonts.packages = with pkgs; [
    (nerdfonts.override {
      fonts = [
        "FiraCode"
        "VictorMono"
      ];
    })
  ];
  nix.settings.experimental-features = "nix-command flakes";
  nix.settings = {
    substituters = [
      "https://nix-community.cachix.org"
      "https://cache.nixos.org/"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  nix.package = pkgs.nix;

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
