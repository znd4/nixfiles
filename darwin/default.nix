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
    nerd-fonts.fira-code
    nerd-fonts.victor-mono
  ];

  nix.settings.experimental-features = "nix-command flakes ca-derivations";
  nix.settings = {
    substituters = [
      "https://nix-community.cachix.org"
      "https://cache.nixos.org/"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    extra-platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
  nix.package = pkgs.nix;

  system.stateVersion = stateVersion;

  services.nix-daemon.enable = true;

  environment.systemPackages = with pkgs; [ qemu ];

  programs.fish.enable = true;
  programs.zsh.enable = true;

  homebrew = {
    enable = true;
    casks = [ "1password-cli" ];
  };
  # environment.postBuild
}
