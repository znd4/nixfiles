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
          "znd4@nixos" = home-manager.lib.homeManagerConfiguration {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
            extraSpecialArgs = { inherit inputs; outputs = self; username = "znd4"; stateVersion = "23.05"; };
            modules = [
              ./home-manager/home.nix
            ];
          };
        };
    };
}
