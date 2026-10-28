# Go point releases that no nixpkgs pin carries yet, for packages whose go.mod
# asks for one (glab's tracks the newest patch release). Each entry becomes
# `go_<v>` and `buildGo<v>Module`, e.g. `go_1_27_3` / `buildGo1_27_3Module`.
#
# These reuse the packaging from `nixpkgs-glab`, the newest pin, with only the
# source tarball moved, so each one is a local Go build. To add a version, take
# the "source" sha256 from https://go.dev/dl/?mode=json and convert it with
# `nix hash convert --hash-algo sha256 --to sri <hex>`. Drop an entry once a
# pin has that Go.
{ inputs, system, ... }:
let
  pinned = inputs.nixpkgs-glab.legacyPackages.${system};
  inherit (pinned) lib;

  versions = {
    "1.27.3" = {
      base = pinned.go_1_27;
      hash = "sha256-bndJA1zzYPBrJXXRYup535/ajvZxiJ5cN1+OUHd/Jrs=";
    };
  };
in
(
  final: prev:
  lib.concatMapAttrs (
    version:
    { base, hash }:
    let
      attr = lib.replaceStrings [ "." ] [ "_" ] version;
      go = base.overrideAttrs (_: {
        inherit version;
        src = pinned.fetchurl {
          url = "https://go.dev/dl/go${version}.src.tar.gz";
          inherit hash;
        };
      });
    in
    {
      "go_${attr}" = go;
      "buildGo${attr}Module" = pinned.buildGoModule.override { inherit go; };
    }
  ) versions
)
