{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nil.url = "github:oxalica/nil";

    hyprland = {
      # url = "github:hyprwm/Hyprland";
      type = "github";
      owner = "hyprwm";
      repo = "Hyprland";
      ref = "v0.35.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hypridle = {
      url = "github:hyprwm/hypridle";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin.url = "github:LnL7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

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

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      darwin,
      ...
    }@inputs:
    let
      lib = nixpkgs.lib;
    in
    {
      keys = {
        "github.com" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkoZGPqvCciloARGk9/rgPdjCFI2JmsYbgboEv98RKc github.com key";
      };
      darwinModules = {
        default = ./darwin;
      };
      darwinFactory =
        {
          system ? "aarch64-darwin",
          extraModules ? [ ],
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
          modules = [ self.darwinModules.default ] ++ extraModules;
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
              }:
              (lib.attrsets.nameValuePair hostname (
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
                hostname = "t470";
                username = "znd4";
              }
            ]
        )
      );
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-rfc-style;

      homeModules = {
        default = ./home-manager;
      };
      homeConfigurationFactory =
        {
          system,
          username,
          hostname,
          keys ? self.keys,
          stateVersion ? "23.11",
          extraModules ? [ ],
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
          modules = [ self.homeModules.default ] ++ extraModules;
        };
      homeConfigurations = (
        builtins.listToAttrs (
          builtins.map
            (
              {
                username,
                hostname,
                system ? "x86_64-linux",
              }:
              (lib.attrsets.nameValuePair "${username}@${hostname}" (
                self.homeConfigurationFactory { inherit system username hostname; }
              ))
            )
            [
              {
                username = "znd4";
                hostname = "t470";
              }
            ]
        )
      );
    };
}
