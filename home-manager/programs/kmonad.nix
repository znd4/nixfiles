{ pkgs, inputs, ... }:
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
  home.packages = with pkgs; [
    kmonad
    (writeShellScriptBin "km" ''
      #!/usr/bin/env bash
      kmonad --config ${kmonadConfig}
    '')

  ];

}
