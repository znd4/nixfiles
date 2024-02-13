{ lib, pkgs, inputs, username, ... }: {
  nixpkgs.overlays = [ inputs.kmonad.overlays.default ];
  environment.systemPackages = with pkgs; [ kmonad ];
  # environment.postBuild = [
  #   lib.strings.escapeShellArgs
  #   [
  #     "${pkgs.kmonad}/bin/kmonad"
  #     (pkgs.writeTextFile {
  #       name = "kmonad.kbd";
  #       text = ''
  #         (defcfg
  #          input (iokit-name "Apple Internal Keyboard / Trackpad")
  #          output (kext)
  #          fallthrough true
  #         )
  #         ${builtins.readFile
  #         "${inputs.dotfiles}/xdg-config/.config/kmonad/config.kbd"}
  #       '';
  #     })
  #   ]
  # ];
  launchd.user.agents.kmonad = {
    script = lib.strings.escapeShellArgs [
      # "echo"
      # "kmonad"
      "/Users/${username}/.nix-profile/bin/kmonad"
      "--log-level=debug"
      (pkgs.writeTextFile {
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
      })
    ];
    environment = { PATH = "/Users/${username}/.nix-profile/bin"; };
    # path = [ pkgs.kmonad ];
    serviceConfig = {
      UserName = "root";
      StandardOutPath = "/tmp/kmonad.out";
      StandardErrorPath = "/tmp/kmonad.err";
      Debug = true;
      KeepAlive = true;
    };
  };
}
