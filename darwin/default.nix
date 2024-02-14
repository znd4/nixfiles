{ pkgs, lib, inputs, username, ... }: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
  };
  nix.settings.experimental-features = "nix-command flakes";
  services.nix-daemon.enable = true;
  nixpkgs.overlays = [ inputs.kmonad.overlays.default ];
  environment.systemPackages = with pkgs; [
    fish
    zsh
    git
  ];
  environment.loginShell = "fish --login";
  # environment.postBuild 
}
