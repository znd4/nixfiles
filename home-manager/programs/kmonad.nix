{ pkgs, inputs, username, ... }: {

  home.packages = [ pkgs.haskellPackages.kmonad ];
  # systemd.user.services.kmonad = {
  #   Service = {
  #     ExecStart =
  #       "${pkgs.haskellPackages.kmonad}/bin/kmonad --config ${inputs.kmonad-config}";
  #     Restart = "always";
  #     RestartSec = "10";
  #   };
  # };
}
