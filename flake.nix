{

  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";
  inputs.dotfiles={
      flake=false;
      url = "path:./dotfiles";
  };

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
          stateVersion = "23.11";
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
            extraSpecialArgs = { inherit inputs; outputs = self; username = "znd4"; stateVersion = "23.11"; };
            modules = [
              ./home-manager/home.nix
            ];
          };
        };
    };
}
