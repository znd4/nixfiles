{
  pkgs,
  inputs,
  system,
  ...
}:
{
  nixpkgs.overlays = [
    (final: prev: {
      poetry = inputs.nixpkgs-unstable.legacyPackages.${system}.poetry;
      dagger = inputs.dagger.packages.${system}.dagger;
      uv = inputs.nixpkgs-unstable.legacyPackages.${system}.uv;
      opentofu = inputs.nixpkgs-unstable.legacyPackages.${system}.opentofu;
      tflint = inputs.nixpkgs-unstable.legacyPackages.${system}.tflint;
      kubernetes-helm = inputs.nixpkgs-unstable.legacyPackages.${system}.kubernetes-helm;
      terragrunt = inputs.nixpkgs-unstable.legacyPackages.${system}.terragrunt;
    })
  ];

  home.packages =
    with pkgs;
    let
      argocd = inputs.nixos-unstable.legacyPackages.${system}.argocd;
      sessionx = inputs.sessionx.packages.${system}.default;
      spacectl = inputs.nixpkgs-unstable.legacyPackages.${system}.spacectl;
      terragrunt-atlantis-config = inputs.self.packages.${system}.terragrunt-atlantis-config;
      personal_scripts = (
        buildEnv {
          name = "myScripts";
          paths = [ "${inputs.self}/dotfiles/scripts/.local" ];
        }
      );
    in
    [
      # kmonad
      age
      alejandra
      argocd
      asdf
      awsume
      aws-sso-util
      bat
      bottom
      broot
      buildpack
      cargo
      chart-testing
      clipboard-jh
      cobra-cli
      commitizen
      conftest
      crossplane-cli
      cue
      dagger
      delta
      devbox
      devenv
      dyff
      fd
      flyctl
      fnm
      gcc
      git
      git-credential-oauth
      git-open
      git-town
      glab
      glow
      gnumake
      go-task
      (google-cloud-sdk.withExtraComponents (
        with google-cloud-sdk.components;
        [
          gke-gcloud-auth-plugin
        ]
      ))
      gum
      helmfile
      home-manager
      htop
      jc
      jq
      jsonnet-bundler
      just
      kubectl
      kubernetes-helm
      nixfmt-rfc-style
      nodejs
      nodePackages_latest.cdk8s-cli
      opam
      opentofu
      open-policy-agent
      parallel
      pay-respects
      personal_scripts
      pnpm
      podman-compose
      poetry
      pre-commit
      python-launcher
      regal
      ruff
      rustc
      sd
      sesh
      sessionx
      skim
      sops
      spacectl
      stow
      stylua
      talosctl
      tanka
      telescope-filter
      terraform
      terraform-docs
      terragrunt
      terragrunt-atlantis-config
      tflint
      tilt
      timoni
      unzip
      uv
      vale
      vulnix
      wget
      xh
      yamale
      yq-go
      zenith
      # zig
      zk
      zoxide
      zsh
    ];
}
