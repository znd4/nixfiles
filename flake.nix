{
  inputs = {
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

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

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      darwin,
      ...
    }@inputs:

    {
      keys = {
        "github.com" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkoZGPqvCciloARGk9/rgPdjCFI2JmsYbgboEv98RKc github.com key";
      };
      darwinModules = [
        ./darwin
        # Inline set home-manager to invocation of (import ./home-manager/darwin.nix)
        home-manager.darwinModules.home-manager
        (
          {
            inputs,
            keys,
            username,
            hmStateVersion,
            ...
          }:
          {
            # home-manager.useGlobalPkgs = true;
            # home-manager.useUserPackages = true;
            home-manager.users.dufourz = {
              imports = [ ./home-manager/default.nix ];
              _modules.args = {
                inherit
                  inputs
                  keys
                  username
                  hmStateVersion
                  ;
              };
            };
          }
        )
      ];
      darwinConfigFactory =
        {
          system,
          modules ? [ ],
          specialArgs,
          ...
        }:
        assert specialArgs ? inputs;
        assert specialArgs ? keys;
        assert specialArgs ? username;
        assert specialArgs ? hmStateVersion;
        darwin.lib.darwinSystem {
          system = system;
          modules = modules ++ self.darwinModules;
          specialArgs = specialArgs;
        };
      darwinConfigurations.work = self.darwinConfigFactory {
        inherit inputs;
        system = "aarch64-darwin";
        modules = [ ];
        specialArgs = {
          inherit inputs;
          hmStateVersion = "23.11";
          keys = self.keys;
          username = "dufourz";
          stateVersion = 4;
        };
      };
      nixosConfigurations.nixos =
        let
          system = "x86_64-linux";
        in
        nixpkgs.lib.nixosSystem {
          system = system;
          specialArgs = {
            inherit inputs;
            system = system;
            outputs = self;
            stateVersion = "23.11";
            username = "znd4";
            machineName = "t470";
          };
          modules = [
            ./nixos
            ./shell
          ];
        };
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-rfc-style;
      homeModules = {
        shared = (import ./home-manager/shared.nix);
      };
      homeConfigurations = {
        "znd4@nixos" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          extraSpecialArgs = {
            inherit inputs;
            username = "znd4";
            system = "x86_64-linux";
            keys = self.keys;
            stateVersion = "23.11";
          };
          modules = [ ./home-manager/default.nix ];
        };
      };
    };
}
