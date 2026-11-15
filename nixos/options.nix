# Per-host knobs for the NixOS configuration. A host module (see ./hosts)
# sets them; feature modules in ./modules declare their own enable options.
{ lib, ... }:
{
  options.znd4.username = lib.mkOption {
    type = lib.types.str;
    example = "znd4";
    description = "Login name of the machine's main user.";
  };
}
