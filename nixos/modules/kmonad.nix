{ inputs, hostname, ... }:
let
  keyboardMap = {
    "t470" = "/dev/input/by-path/platform-i8042-serio-0-event-kbd";
  };
  enabled = builtins.hasAttr hostname keyboardMap;
in
if !enabled then {} else
{
  imports = [ inputs.kmonad.nixosModules.default ];
  services.kmonad =
    let
    in
    {
      enable = true;
      keyboards = {
        "kmonad-keeb" = {
          device = keyboardMap.${hostname};
          config = ''
            (defcfg
              ;; For Linux
              input  (device-file "${keyboardMap.${hostname}}")
              output (uinput-sink "My KMonad output"
                ;; To understand the importance of the following line, see the section on
                ;; Compose-key sequences at the near-bottom of this file.
                ;; "/run/current-system/sw/bin/sleep 1 && /run/current-system/sw/bin/setxkbmap -option compose:ralt"
                )
              cmp-seq ralt    ;; Set the compose key to `RightAlt'
              cmp-seq-delay 5 ;; 5ms delay between each compose-key sequence press

              ;; For Windows
              ;; input  (low-level-hook)
              ;; output (send-event-sink)

              ;; For MacOS
              ;; input  (iokit-name "my-keyboard-product-string")
              ;; output (kext)

              ;; Comment this if you want unhandled events not to be emitted
              fallthrough true

              ;; Set this to false to disable any command-execution in KMonad
              allow-cmd true
            )
            ${builtins.readFile "${inputs.dotfiles}/xdg-config/.config/kmonad/config.kbd"}
          '';
        };
      };
      # Modify the following line if you copied nixos-module.nix elsewhere or if you want to use the derivation described above
      # package = import /pack/to/kmonad.nix;
    };
  # for kmonad
  users.groups.uinput = { };
  services.udev.extraRules = ''
    # KMonad user access to /dev/uinput
    KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
  '';
}
