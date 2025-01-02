{ pkgs, inputs, ... }:
let
  lib = pkgs.lib;
in
(lib.attrsets.genAttrs (builtins.filter (f: f != "default.nix") (
  builtins.attrNames (builtins.readDir ./.)
)) (name: ((import (./. + "/${name}")) { inherit pkgs inputs; })))
