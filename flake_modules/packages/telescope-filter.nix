{
  inputs,
  ...
}:
{
  imports = [
    inputs.flake-parts.flakeModules.easyOverlay
  ];
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      overlayAttrs = {
        inherit (config.packages) telescope-filter;
      };
      packages.telescope-filter = (
        pkgs.writeShellApplication (
          let
            nvim_temp = inputs.nixvim.legacyPackages.${pkgs.system}.makeNixvim {
              plugins = {
                web-devicons.enable = true;
                telescope = {
                  enable = true;
                  settings = {
                    defaults = {
                      layout_config = {
                        horizontal = {
                          height = 0.99;
                          width = 0.99;
                        };
                        vertical = {
                          height = 0.99;
                          width = 0.99;
                        };
                      };
                    };
                  };
                };
              };
            };
          in
          {
            name = "telescope-filter";
            runtimeInputs = [
              nvim_temp
            ];
            text = builtins.readFile "${inputs.self}/scripts/telescope-filter.sh";
            runtimeEnv = {
              NVIM = "${nvim_temp}/bin/nvim";
            };
          }
        )
      );

    };
}
