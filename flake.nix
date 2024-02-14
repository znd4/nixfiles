{
  inputs = {
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:LnL7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    kmonad.url = "git+https://github.com/kmonad/kmonad?submodules=1&dir=nix";

    dotfiles = {
      flake = false;
      url = "path:./dotfiles";
    };
  };

  # inputs.kmonad = {
  #   url = "github:kmonad/kmonad";
  #   flake = false;
  # };
  # inputs.kmonad.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, home-manager, darwin, ... }@inputs:

    {
      darwinConfigurations = {
        work = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            ./darwin
            # Inline set home-manager to invocation of (import ./home-manager/darwin.nix)
            home-manager.darwinModules.home-manager
            {
              # home-manager.useGlobalPkgs = true;
              # home-manager.useUserPackages = true;
              _module.args = {
                inherit inputs;
                username = "dufourz";
                stateVersion = "23.11";
              };
              home-manager.users.dufourz = (import ./home-manager/darwin.nix) {
                inherit inputs;
                username = "dufourz";
                stateVersion = "23.11";
              };
            }
          ];
          specialArgs = {
            inherit inputs;
            username = "dufourz";
            stateVersion = "23.11";
          };
        };
      };
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          outputs = self;
          stateVersion = "23.11";
          username = "znd4";
          machineName = "t470";
        };
        modules = [ ./nixos ./shell ];
      };
      homeConfigurations = let
        # TODO - define closure that accepts username and system as arguments
      in {
        "znd4@nixos" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          extraSpecialArgs = {
            inherit inputs;
            outputs = self;
            username = "znd4";
            stateVersion = "23.11";
          };
          modules = [ ./home-manager/nixos.nix ];
        };
      };
    };
}
