{ lib, config, pkgs, inputs, ... }: {

  programs.fish.enable = lib.mkDefault true;
  programs.starship.enable = true;
  programs.skim.fuzzyCompletion = true;


  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withPython3 = true;
    withNodeJs = true;
  };

  environment.systemPackages = with pkgs; [
    inputs.home-manager.packages.${pkgs.system}.default
  ];
}
