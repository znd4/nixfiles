{
  pkgs,
  inputs,
  system,
  ...
}:
(final: prev: {
  # git-town = prev.git-town.overrideAttrs (oldAttrs: {
  git-town =
    let
      git-town = inputs.nixpkgs-git-town-21_1_0.legacyPackages.${system}.git-town;
    in
    git-town.overrideAttrs (oldAttrs: {
      buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ prev.makeWrapper ];
      postInstall = ''
        ${oldAttrs.postInstall or ""}
        rm $out/bin/git-town
        makeWrapper ${git-town}/bin/git-town $out/bin/git-town \
          --run 'export GITHUB_AUTH_TOKEN=$(op read "op://Personal/GitHub Personal Access Token/token")'
      '';
    });
})
