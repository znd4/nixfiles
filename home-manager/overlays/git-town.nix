{
  pkgs,
  ...
}:
(final: prev: {
  git-town = prev.git-town.overrideAttrs (oldAttrs: {
    buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ prev.makeWrapper ];
    postInstall = ''
      ${oldAttrs.postInstall or ""}
      rm $out/bin/git-town
      makeWrapper ${prev.git-town}/bin/git-town $out/bin/git-town \
        --run 'export GITHUB_AUTH_TOKEN=$(op read "op://Personal/GitHub Personal Access Token/token")'
    '';
  });
})
