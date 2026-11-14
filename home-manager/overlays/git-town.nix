{
  pkgs,
  inputs,
  ...
}:
(final: prev: {
  # git-town = prev.git-town.overrideAttrs (oldAttrs: {
  git-town =
    inputs.nixpkgs-git-town-21_2_0.legacyPackages.${prev.stdenv.hostPlatform.system}.git-town;
})
