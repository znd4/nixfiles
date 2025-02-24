{
  pkgs,
  ...
}:
(final: prev: {
  git-town = pkgs.writeShellScriptBin "git-town" ''
    GITHUB_AUTH_TOKEN=$(op read "op://Personal/GitHub Personal Access Token/token") ${prev.git-town}/bin/git-town "$@"
  '';
})
