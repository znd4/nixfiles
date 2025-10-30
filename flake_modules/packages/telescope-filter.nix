{
  inputs,
  ...
}:
{
  # imports = [
  #   inputs.flake-parts.flakeModules.easyOverlay
  # ];
  # perSystem =
  #   {
  #     config,
  #     pkgs,
  #     ...
  #   }:
  #   {
  #     overlayAttrs = {
  #       inherit (config.packages) telescope-filter;
  #     };
  #     packages.telescope-filter = (
  #       pkgs.writeShellApplication (
  #         let
  #           nvim_temp = inputs.nixvim.legacyPackages.${pkgs.system}.makeNixvim {
  #             plugins = {
  #               web-devicons.enable = true;
  #               telescope.enable = true;
  #             };
  #           };
  #         in
  #         {
  #           name = "telescope-filter";
  #           runtimeInputs = [
  #             nvim_temp
  #           ];
  #           text = builtins.readFile "${inputs.self}/scripts/telescope-filter.sh";
  #           runtimeEnv = {
  #             NVIM = "${nvim_temp}/bin/nvim";
  #           };
  #         }
  #       )
  #     );
  #
  #   };
}
