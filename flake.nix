{
  nixConfig = {
    extra-substituters = ["https://hyprland.cachix.org"];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nil.url = "github:oxalica/nil";
    nixd = {
      url = "github:nix-community/nixd";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      # url = "github:hyprwm/Hyprland";
      type = "github";
      owner = "hyprwm";
      repo = "Hyprland";
      ref = "v0.36.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hypridle = {
      url = "github:hyprwm/hypridle";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins.url = "github:hyprwm/hyprland-plugins";
    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sesh = {
      url = "github:joshmedeski/sesh";
      flake = false;
    };
    sessionx = {
      url = "github:omerxx/tmux-sessionx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kmonad = {
      url = "git+https://github.com/kmonad/kmonad?submodules=1&dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

  outputs = {
    flake-parts,
    nixpkgs,
    darwin,
    home-manager,
    self,
    ...
  } @ inputs: let
    lib = nixpkgs.lib;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      perSystem = {
        config,
        pkgs,
        ...
      }: {
        formatter = pkgs.alejandra;
      };
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      flake = {
        keys = {
          "github.com" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkoZGPqvCciloARGk9/rgPdjCFI2JmsYbgboEv98RKc github.com key";
        };
        darwinModules = {
          default = ./darwin;
        };
        darwinFactory = {
          system ? "aarch64-darwin",
          extraModules ? [],
          username,
          stateVersion,
        }:
          darwin.lib.darwinSystem {
            system = system;
            inherit inputs;
            specialArgs = {
              inherit inputs;
              username = username;
              stateVersion = stateVersion;
              system = system;
            };
            modules = [self.darwinModules.default] ++ extraModules;
          };
        darwinConfigurations.work = self.darwinFactory {
          username = "dufourz";
          stateVersion = 4;
        };

        nixosConfigurations = (
          builtins.listToAttrs (
            builtins.map
            (
              {
                system ? "x86_64-linux",
                stateVersion ? "23.11",
                username,
                hostname,
              }: (lib.attrsets.nameValuePair hostname (
                lib.nixosSystem {
                  system = system;
                  specialArgs = {
                    inherit inputs;
                    system = system;
                    outputs = self;
                    stateVersion = stateVersion;
                    username = username;
                    hostname = hostname;
                  };
                  modules = [
                    ./nixos
                    ./shell
                  ];
                }
              ))
            )
            [
              {
                hostname = "desktop";
                username = "znd4";
              }
              {
                hostname = "t470";
                username = "znd4";
              }
            ]
          )
        );

        homeModules = {
          default = ./home-manager;
        };
        homeConfigurationFactory = {
          system,
          username,
          hostname,
          keys ? self.keys,
          stateVersion ? "23.11",
          extraModules ? [],
        }:
          home-manager.lib.homeManagerConfiguration {
            pkgs = nixpkgs.legacyPackages.${system};
            extraSpecialArgs = {
              inherit
                inputs
                system
                username
                hostname
                stateVersion
                keys
                ;
            };
            modules = [self.homeModules.default] ++ extraModules;
          };
        homeConfigurations = (
          builtins.listToAttrs (
            builtins.map
            (
              {
                username,
                hostname,
                system ? "x86_64-linux",
              }: (lib.attrsets.nameValuePair "${username}@${hostname}" (
                self.homeConfigurationFactory {inherit system username hostname;}
              ))
            )
            [
              {
                username = "znd4";
                hostname = "desktop";
              }
              {
                username = "znd4";
                hostname = "t470";
              }
            ]
          )
        );
      };
    };
}
