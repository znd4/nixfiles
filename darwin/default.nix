{ pkgs, lib, inputs, username, ... }: {
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    isHidden = false;
    packages = with pkgs; [
      python311Packages.supervisor
    ];
  };
  nix.settings.experimental-features = "nix-command flakes";
  services.nix-daemon.enable = true;
  nixpkgs.overlays = [ inputs.kmonad.overlays.default ];
  # environment.postBuild 
  # launchd.user.agents = {
  #   kmonad = {
  #     script = lib.strings.escapeShellArgs [
  #       # "echo"
  #       # "kmonad"
  #       "/Users/${username}/.nix-profile/bin/kmonad"
  #       "--log-level=debug"
  #       (pkgs.writeTextFile {
  #         name = "kmonad-config-with-header.kbd";
  #         text = ''
  #           ;; comment at beginning
  #           (defcfg
  #             input (iokit-name "Apple Internal Keyboard / Trackpad")
  #             output (kext)
  #             fallthrough true
  #           )
  #           ${builtins.readFile
  #           "${inputs.dotfiles}/xdg-config/.config/kmonad/config.kbd"}
  #         '';
  #       })
  #     ];
  #     environment = {
  #       PATH="/Users/${username}/.nix-profile/bin";
  #     };
  #     # path = [ pkgs.kmonad ];
  #     serviceConfig = {
  #       UserName = "root";
  #       StandardOutPath = "/tmp/kmonad.out";
  #       StandardErrorPath = "/tmp/kmonad.err";
  #       Debug = true;
  #       KeepAlive = true;
  #     };
  #   };
  # };
}
