{ pkgs, lib, inputs, username, ... }: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
  };
  nix.settings.experimental-features = "nix-command flakes";
  services.nix-daemon.enable = true;
  nixpkgs.overlays = [ inputs.kmonad.overlays.default ];
  launchd.user.agents = {
    kmonad = {
      script = lib.strings.escapeShellArgs [
        "kmonad"
        "--log-level=debug"
        (pkgs.writeTextFile {
          name = "kmonad-config-with-header.kbd";
          text = ''
            ;; comment at beginning
            (defcfg
              input (iokit-name)
              output (dext)
              fallthrough true
            )
            ${builtins.readFile
            "${inputs.dotfiles}/xdg-config/.config/kmonad/config.kbd"}
          '';
        })
      ];
      path = [ pkgs.kmonad ];
      serviceConfig = {
        Disable = true;
        UserName = "root";
        StandardOutPath = "/tmp/kmonad.log";
        Debug = true;
        KeepAlive = true;
      };
    };
  };
}
