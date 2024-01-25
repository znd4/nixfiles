{
  inputs.nixos-06cb-009a-fingerprint-sensor = {
    url = "github:ahbnr/nixos-06cb-009a-fingerprint-sensor";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  inputs.home-manager.url = "github:nix-community/home-manager/release-23.05";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self
    , nixpkgs
    , home-manager
    , ...
    } @ inputs:

    let
      stateVersion = "23.11";
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs; outputs = self;
          stateVersion = stateVersion;
          username = "znd4";
        };
        modules = [
          ./configuration.nix
          ./shell
        ];
      };
      homeConfigurations =
        let
          # TODO - define closure that accepts username and system as arguments
        in
        {
          znd4 = home-manager.lib.homeManagerConfiguration {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
            extraSpecialArgs = { inherit inputs; outputs = self; username = "znd4"; stateVersion = stateVersion; };
            modules = [
              ./home-manager/home.nix
            ];
          };
        };
    };
}
