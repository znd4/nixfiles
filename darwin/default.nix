{ pkgs, lib, inputs, username, ... }: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
  };
  imports = [
    ./programs/kmonad.nix
  ];
  nix.settings.experimental-features = "nix-command flakes";
  services.nix-daemon.enable = true;
  nixpkgs.overlays = [ inputs.kmonad.overlays.default ];
  # environment.postBuild 
}
