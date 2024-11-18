{
  inputs,
  username,
  config,
  keys,
  system,
  pkgs,
  lib,
  ...
}:
if !(lib.strings.hasSuffix "darwin" system) then
  { }
else
  {
    imports = (
      builtins.map (f: (import (./. + "/${f}"))) (
        builtins.filter (f: f != "default.nix") (builtins.attrNames (builtins.readDir ./.))
      )

    );

    targets.darwin.defaults = {
      # https://macos-defaults.com/#%F0%9F%92%BB-list-of-commands
      "com.apple.finder" = {
        AppleShowAllFiles = true;
      };
    };

    home.homeDirectory = "/Users/${username}";
    home.sessionPath = [ "${config.home.homeDirectory}/homebrew/bin" ];
  }
