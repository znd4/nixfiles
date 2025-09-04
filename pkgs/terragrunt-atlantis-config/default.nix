{
  pkgs,
  inputs,
  ...
}:
let
  inherit (pkgs) lib buildGoModule;
in

buildGoModule rec {
  pname = "terragrunt-atlantis-config";
  version = "1.20.0";

  src = inputs.terragrunt-atlantis-config;

  vendorHash = "sha256-lxMZ92fEOaDtON9P4he2cPNkh1mb/UOM1PxnBB1htwc=";

  nativeBuildInputs = with pkgs; [ makeWrapper gnumake ];

  checkPhase = ''
    runHook preCheck
    make test
    runHook postCheck
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  meta = with lib; {
    description = "Generate Atlantis config for Terragrunt projects";
    homepage = "https://github.com/transcend-io/terragrunt-atlantis-config";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.unix;
  };
}