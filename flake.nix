{
  inputs = {
    hyprland.url = "github:hyprwm/Hyprland";
    hypridle.url = "github:hyprwm/hypridle";
    hyprlock.url = "github:hyprwm/hyprlock";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";

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
      darwinModules = {
        default = ./darwin;
      };
      darwinConfigurations.work =
        let
          system = "aarch64-darwin";
          specialArgs = {
            inherit inputs;
            keys = self.keys;
            username = "dufourz";
            stateVersion = "23.11";
            system = system;
          };
        in
        darwin.lib.darwinSystem {
          inherit inputs;
          system = system;
          modules = [
            self.darwinModules.default
            {
              # home-manager.useGlobalPkgs = true;
              # home-manager.useUserPackages = true;

              system.stateVersion = 4;
            }
          ];
          specialArgs = specialArgs;
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
        default = ./home-manager;
      };
      homeConfigurations =
        let
          mkConfig =
            { system, username }:
            home-manager.lib.homeManagerConfiguration {
              pkgs = nixpkgs.legacyPackages.${system};
              extraSpecialArgs = {
                inherit inputs;
                system = system;
                username = username;
                keys = self.keys;
                stateVersion = "23.11";
              };
              modules = [ self.homeModules.default ];
            };
        in
        {
          "work" = mkConfig {
            system = "aarch64-darwin";
            username = "dufourz";
          };
          "znd4@nixos" = mkConfig {
            system = "x86_64-linux";
            username = "znd4";
          };
        };
    };
}
