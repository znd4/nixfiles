pkgs:
let
  system = pkgs.stdenv.hostPlatform.system;
  perSystem = {
    "aarch64-darwin" = {
      sha256 = "sha256-XIubL4sBfj/+VKRrjo2LNkeXIrxXctfBsYfEqMhTjgE=";
      arch = "arm64";
      os = "darwin";
    };
    "aarch64-linux" = {
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      arch = "arm64";
      os = "linux";
    };
    "x86_64-darwin" = {
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      arch = "amd64";
      os = "darwin";
    };
    "x86_64-linux" = {
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      os = "linux";
      arch = "amd64";
    };
  };
  arch = perSystem.${system}.arch;
  os = perSystem.${system}.os;
  sha256 = perSystem.${system}.sha256;
in
pkgs.stdenv.mkDerivation rec {
  pname = "akuity";
  version = "v0.18.0";
  src = pkgs.fetchurl {
    url = "https://dl.akuity.io/akuity-cli/${version}/${os}/${arch}/akuity";
    inherit sha256;
  };
  nativeBuildInputs = [ pkgs.installShellFiles ];

  phases = [ "installPhase" ];

  installPhase = ''
    export HOME=$(pwd) # https://github.com/NixOS/nix/issues/670
    install -m 755 -D -- "$src" "$out"/bin/akuity

    # Generate shell completions
    installShellCompletion --cmd akuity \
      --bash <($out/bin/akuity completion bash) \
      --fish <($out/bin/akuity completion fish) \
      --zsh <($out/bin/akuity completion zsh)
  '';

  passthru.tests.version = pkgs.testers.testVersion {
    package = pkgs.akuity;
    command = "akuity version --short";
    version = "v${version}";
  };
}
