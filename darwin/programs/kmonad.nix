{ lib, pkgs, inputs, username, ... }:
let
  kmonadConfig = (pkgs.writeTextFile {
    name = "kmonad-config-with-header.kbd";
    text = ''
      ;; comment at beginning
      (defcfg
       input (iokit-name "Apple Internal Keyboard / Trackpad")
       output (kext)
       fallthrough true
      )
      ${builtins.readFile
      "${inputs.dotfiles}/xdg-config/.config/kmonad/config.kbd"}
    '';
  });
in {
  nixpkgs.overlays = [ inputs.kmonad.overlays.default ];
  environment.shellAliases = {
    km = lib.escapeShellArgs [ "kmonad" kmonadConfig ];
  };
  environment.systemPackages = with pkgs; [
    kmonad
    (lib.writeScript "km" ''
      #!${pkgs.stdenv.shell}
      kmonad ${kmonadConfig}
    '')
  ];
}
