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
    waybar.url = "github:Alexays/Waybar";
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
        knownHosts = {
          "desktop.local" = ''
            desktop.local ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCjzYEuKtErq3irlOePfFj9tcbMSEp8Jkto1GnxQGJeyBwymwJ10THsN4Nidmpz/jne6GtxmXqzhq2577SImhjeN/FTid04js7EZ//vIXn9P0gJ4L70bAQzn1741l5Hg4ChD4h+hYkNh81HIKt59Es4+YA8QG1ktRStftFv/ks5dFQnVXlfapYsJpvxd4AhiyfQu5DdQoo8rPa8ReWQWb9B+CIV4N1ytfaqya3EMuLCJRCwjgDAgz9tDJDIiTSOqHgxtBRP5HGUVCFNXusMgHseVCzl5J5evOl+ZlVtONuxWMwS2uiyIbMXCZvi9qukEN7ukajfAbFFAowaLD9yz9WixLuxG6/Q3IlHJ07z9f4aNr15hLGysNNswGimNqfbBhIwxdc1H1tKUUZTbxNSFWnoOYBokvBQd/a+S1cVr1FmHXn0gbmFeJtCueJyrEHV7pgfxqDmWc3QaeLPhXlHj1WUzTVNcwUzCsRj0kPBNwClR/s9/9ayYexnRoj0i4HnmG/tTLtQEi/IuXiBAkPrTcpouPY83vvhAHUUFMaUXABidX8aIXgxIxnG/afUzGP2YwqSF8yjxIVoZXf+ZdZrT42AJC94/QuU5c48p96Pzd7Luoabt6tfJPx4RH8efGvR8aA1R6NXCbxEoXrPYORIbAyiRugvVxD7eFKc+CQULXcE3w==
          '';
        };
        keys = {
          "github.com" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkoZGPqvCciloARGk9/rgPdjCFI2JmsYbgboEv98RKc github.com key";
          "desktop.local" = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDg1BjrrEL43KwRmH2e4xF7R7XjO3bvG2ysJ3lk0XKmAtvmMGgBcQYwS2Q1/0rLKtnFNoYQA2koPoxGzHgW7qSxY0ltMs6FIDwfSdpJCeMy+NiayL30Lqu2zaM3SFsDC8TeSWv3kZdPr+RY/gUELiYx8VR4ZNd//Ykuu5+/rckO5bkqaT8iC8WzouLYSpwecTb2kAvyj1mrBSQH1QHqcowlDPwqGyCKh1CMTlX/jxEUOPpBrxhVFBiFFVnUJC28Kr+ggq8V34PiS+N/+QD+mCx6w71BfzV4JLl3NTclYWbg8ngxFE5olIKwpL0YZz/0ViW35KNhlAbI3IMbVeZTLKfCVJwMsV8GDuxTX81ypJO3VAPpjUQJ/4VnURqe+8zjBYhFzYJQBU9quCtQQnx7rM/0eav9a0op405cwFrhDc2fcuoD4egwyplm3hgacCGLSmCCk7Y5xSjaeO5MQpSgnVl+kdBXeZnWX5NrTqdlWcuW898Ijd0SLzidURvFjUauuprpk2QvnPw9oJivpC1HjVvPkYClBFqLwrjTQWtAACiBaFVKvQKygqzYfWYPz4gqO8EZQIuz+YZz/TftAhMDDNh9auo0vA3AaIwd7U972wnzq7/WfNo2SUacZoUerhMJlpPhpV5H54St3S9lfcwTVbZiX7wFsUu8FsO7wBguSFV4yQ==";
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
