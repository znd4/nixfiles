{
  pkgs,
  inputs,
  system,
  ...
}:
{
  nixpkgs.overlays = [
    (final: prev: {
      claude-code =
        (import inputs.nixpkgs-unstable {
          inherit system;
          config = {
            allowUnfree = true;
            allowUnfreePredicate = _: true;
          };
        }).claude-code;
    })
  ];

  home.packages =
    with pkgs;
    let
      argocd = inputs.nixos-unstable.legacyPackages.${system}.argocd;
      tilt = inputs.nixpkgs-tilt-completions.legacyPackages.${system}.tilt;
      sessionx = inputs.sessionx.packages.${system}.default;
      spacectl = inputs.nixpkgs-trunk.legacyPackages.${system}.spacectl;
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
      bat
      bottom
      broot
      buildpack
      cargo
      chart-testing
      claude-code
      clipboard-jh
      cobra-cli
      cue
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
      opam
      opentofu
      personal_scripts
      pnpm
      podman-compose
      poetry
      pre-commit
      python-launcher
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
      tflint
      thefuck
      tilt
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
      zoxide
      zsh
    ];
}
