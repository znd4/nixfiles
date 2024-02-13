{ ... }: {
  imports = builtins.map (f: (import ./. + "/{f}"))
    (builtins.filter (f: f != "default.nix")
      (builtins.attrNames (builtins.readDir ./.)));
}
