{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Imported on every platform: imports cannot depend on pkgs. Each file
  # here must apply only on Darwin by itself.
  imports = (
    builtins.map (f: (import (./. + "/${f}"))) (
      builtins.filter (f: f != "default.nix") (builtins.attrNames (builtins.readDir ./.))
    )
  );

  config = lib.mkIf pkgs.stdenv.isDarwin {
    targets.darwin.defaults = {
      # https://macos-defaults.com/#%F0%9F%92%BB-list-of-commands
      "com.apple.finder" = {
        AppleShowAllFiles = true;
      };
    };

    home.homeDirectory = "/Users/${config.home.username}";
    home.sessionPath = [ "${config.home.homeDirectory}/homebrew/bin" ];
  };
}
