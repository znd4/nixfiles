{
  inputs,
  hostname,
  pkgs,
  ...
}:
let
  keyboardMap = {
    "t470" = "/dev/input/event0";
    # "t470" = "/dev/input/by-path/platform-i8042-serio-0-event-kbd";
  };
  enabled = builtins.hasAttr hostname keyboardMap;
in
if !enabled then
  { }
else
  {
    imports = [ inputs.miryoku_kmonad.nixosModules.default ];
    services.miryoku_kmonad = {
      enable = true;
      device = keyboardMap.${hostname};
      name = "builtin-keyboard";
      package = pkgs.miryoku_kmonad.overrideAttrs (old: {
        buildFlags = [
          # "MIRYOKU_ALPHAS=QWERTY"
          # "MIRYOKU_NAV=VI"
        ];
      });
    };
  }
