# Paths, not `import`ed functions, so that error messages and the option
# docs name the file that declares an option.
{ lib, ... }:
{
  imports = (
    builtins.map (f: ./. + "/${f}") (
      builtins.filter (f: f != "default.nix") (builtins.attrNames (builtins.readDir ./.))
    )

  );
}
