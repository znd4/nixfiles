{
  inputs = {
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sesh = {
      url = "github:joshmedeski/sesh";
      flake = false;
    };
    sessionx = {
      url = "github:omerxx/tmux-sessionx";
      flake = true;
    };

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
      keys = {
        "github.com" =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkoZGPqvCciloARGk9/rgPdjCFI2JmsYbgboEv98RKc github.com key";
      };
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
              home-manager.users.dufourz = (import ./home-manager/darwin.nix) {
                inherit inputs;
                keys = self.keys;
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
      homeModules = { shared = (import ./home-manager/shared.nix); };
      homeConfigurations = let
        # TODO - define closure that accepts username and system as arguments
      in {
        "znd4@nixos" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          extraSpecialArgs = {
            inherit inputs;
            username = "znd4";
            system = "x86_64-linux";
            keys = self.keys;
            stateVersion = "23.11";
          };
          modules = [ ./home-manager/nixos.nix ];
        };
      };
    };
}
