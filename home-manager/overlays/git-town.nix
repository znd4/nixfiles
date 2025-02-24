{
  pkgs,
  ...
}:
(final: prev: {
  git-town = pkgs.writeShellApplication {
    name = "git-town";
    runtimeInputs = with pkgs; [ bash ];
    derivationArgs = {
      nativeBuildInputs = [ pkgs.installShellFiles ];
      postInstall = ''
        installShellCompletion \
          --cmd git-town \
          --bash <(${prev.git-town}/bin/git-town completions bash) \
          --fish <(${prev.git-town}/bin/git-town completions fish) \
          --zsh <(${prev.git-town}/bin/git-town completions zsh)
      '';
    };
    text = ''
      GITHUB_AUTH_TOKEN=$(op read "op://Personal/GitHub Personal Access Token/token") ${prev.git-town}/bin/git-town "$@"
    '';
  };
})
