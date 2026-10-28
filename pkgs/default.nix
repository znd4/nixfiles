# Each entry here is either a package, exported under its directory name, or
# an attrset of packages (e.g. ./go), merged in as-is.
{ pkgs, inputs, ... }:
let
  lib = pkgs.lib;
in
lib.concatMapAttrs (
  name: _:
  let
    result = (import (./. + "/${name}")) { inherit pkgs inputs; };
  in
  if lib.isDerivation result then { ${name} = result; } else result
) (lib.filterAttrs (name: _: name != "default.nix") (builtins.readDir ./.))
