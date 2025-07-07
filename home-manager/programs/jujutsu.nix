{ inputs, system, ... }:
{
  programs.jujutsu.enable = true;
  programs.jujutsu.package = inputs.nixos-unstable.legacyPackages.${system}.jujutsu;
  programs.jujutsu.settings = {
    user = {
      email = "zane@znd4.dev";
      name = "Zane Dufour";
    };
  };
}
