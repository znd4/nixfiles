{
  pkgs,
  inputs,
  system,
  ...
}:
(final: prev: {
  # git-town = prev.git-town.overrideAttrs (oldAttrs: {
  git-town = inputs.nixpkgs-git-town-21_2_0.legacyPackages.${system}.git-town;
})
