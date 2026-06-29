{
  inputs,
  system,
  ...
}:
{
  # herdr — terminal agent multiplexer (github:ogulcancelik/herdr). Installed
  # from its own flake, pinned to a release tag in flake.nix.
  home.packages = [ inputs.herdr.packages.${system}.default ];
}
