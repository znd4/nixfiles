# Go point releases that no nixpkgs pin carries yet, for packages whose go.mod
# asks for one (glab's tracks the newest patch release). Each `<v>.nix` here
# becomes the flake package `go_<v>`, e.g. 1_27_3.nix -> go_1_27_3, built from
# the go.dev source tarball with the newest pin's packaging for that minor
# release (`nixpkgs-glab`'s go_1_27 for 1.27.x), so each one is a local build.
#
# To add one, create `<v>.nix` containing `{ hash = "..."; }`: the "source"
# sha256 from https://go.dev/dl/?mode=json, converted with
# `nix hash convert --hash-algo sha256 --to sri <hex>`. Delete it once a pin
# carries that Go.
{ pkgs, inputs, ... }:
let
  inherit (pkgs) lib;
  pinned = inputs.nixpkgs-glab.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  mkGo =
    file:
    let
      attr = lib.removeSuffix ".nix" file;
      version = lib.replaceStrings [ "_" ] [ "." ] attr;
      base = pinned."go_${lib.versions.major version}_${lib.versions.minor version}";
    in
    lib.nameValuePair "go_${attr}" (
      base.overrideAttrs (_: {
        inherit version;
        src = pinned.fetchurl {
          url = "https://go.dev/dl/go${version}.src.tar.gz";
          inherit (import (./. + "/${file}")) hash;
        };
      })
    );
in
lib.listToAttrs (
  map mkGo (builtins.filter (f: f != "default.nix") (builtins.attrNames (builtins.readDir ./.)))
)
