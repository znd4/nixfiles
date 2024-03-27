{
  pkgs,
  inputs,
  ...
}: {
  nixpkgs.overlays = [
    (final: prev: {
      sesh = (
        pkgs.buildGoModule {
          src = "${inputs.sesh}";
          name = "sesh";
          vendorHash = "sha256-zt1/gE4bVj+3yr9n0kT2FMYMEmiooy3k1lQ77rN6sTk=";
        }
      );
    })
  ];
  home.packages = with pkgs; [
    sesh
  ];
  xdg.configFile = {
    "sesh/sesh.toml".text = "";
  };
}
