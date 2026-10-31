# Repo picker -> clone into ~/Work/<host>/<path> -> open as a sesh session or
# herdr workspace. Bound to tmux M-m and herdr alt+m.
{ pkgs, ... }:
pkgs.buildGoModule {
  pname = "clone-pick";
  version = "0.1.0";
  src = pkgs.lib.fileset.toSource {
    root = ./.;
    fileset = pkgs.lib.fileset.fileFilter (
      f: f.hasExt "go" || f.name == "go.mod" || f.name == "go.sum"
    ) ./.;
  };
  vendorHash = "sha256-eqd1e6rzY1RdcmkpaRlmFIOKS3w19mphJ8aRgVXW8Q8=";
  nativeBuildInputs = [ pkgs.makeWrapper ];
  # git/gh/glab are called at run time; sesh and herdr come from the caller's PATH.
  postInstall = ''
    wrapProgram $out/bin/clone-pick \
      --suffix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.git
          pkgs.gh
          pkgs.glab
        ]
      }
  '';
  meta.mainProgram = "clone-pick";
}
