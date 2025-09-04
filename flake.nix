{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
    sesh = {
      url = "github:znd4/sesh";
      inputs.nixpkgs.follows = "nixpkgs";
      flake = false;
    };
    ghostty = {
      url = "github:ghostty-org/ghostty";
    };
    dagger.url = "github:dagger/nix";
    dagger.inputs.nixpkgs.follows = "nixpkgs";

    ghostty-hm-module.url = "github:znd4/ghostty-hm-module";
    git-town-znd4.url = "github:znd4/git-town/home-manager";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11"; # Match your nixpkgs version
      inputs.nixpkgs.follows = "nixpkgs"; # Ensure it uses the same nixpkgs
    };

    pre-commit.url = "github:znd4/nixpkgs/feat/pre-commit/add-pip-system-certs";
    # nixpkgs.url = nixos_unstable_url;
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05-small";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable-small";
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-trunk.url = "github:NixOS/nixpkgs/master";
    nixpkgs-24_11.url = "github:NixOS/nixpkgs/nixos-24.11-small";
    nixpkgs-opencode.url = "github:NixOS/nixpkgs/1f0f25154225df0302adcd7b8110ad2c99e48adc";
    # nixpkgs-git-town-21_1_0.url = "github:nixos/nixpkgs/pull/419405/head";
    nixpkgs-git-town-21_2_0.url = "github:znd4/nixpkgs/git-town-21.2.0";

    nil.url = "github:oxalica/nil";
    nil.inputs.nixpkgs.follows = "nixpkgs";
    nixd = {
      url = "github:nix-community/nixd";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    xdg-config = {
      url = "github:znd4/xdg-config";
      flake = false;
    };

    gh-s = {
      url = "github:gennaro-tedesco/gh-s";
      flake = false;
    };
    gh-f = {
      url = "github:gennaro-tedesco/gh-f";
      flake = false;
    };
    sessionx = {
      url = "github:omerxx/tmux-sessionx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    terragrunt-atlantis-config = {
      url = "github:transcend-io/terragrunt-atlantis-config/v1.20.0";
      flake = false;
    };
    darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      flake-parts,
      nixpkgs,
      darwin,
      home-manager,
      self,
      ...
    }@inputs:
    let
      lib = nixpkgs.lib;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
        ./flake_modules
      ];
      perSystem =
        { config, pkgs, ... }:
        {
          formatter = pkgs.nixfmt-rfc-style;
          packages = (import ./pkgs { inherit pkgs inputs; }) // {
            nixos-rebuild-switch = pkgs.writeShellApplication {
              name = "nixos-rebuild-switch";
              runtimeInputs = with pkgs; [
                expect
                nix-output-monitor
              ];
              text = ''
                #!/usr/bin/env bash
                sudo unbuffer nixos-rebuild switch --flake "''${1:-.}" |& nom
              '';
            };
            nix-darwin-switch = pkgs.writeShellApplication {
              name = "nix-darwin-switch";
              runtimeInputs = with pkgs; [
                expect
                darwin.packages.${pkgs.system}.darwin-rebuild
                nix-output-monitor
              ];
              text = ''
                #!/usr/bin/env bash
                set -euo pipefail
                set -x
                unbuffer darwin-rebuild switch --flake "''${1:-.}" |& nom
              '';
            };
            home-manager-switch = pkgs.writeShellApplication {
              name = "home-manager-switch";
              runtimeInputs = with pkgs; [
                expect
                home-manager
                nix-output-monitor
              ];
              text = ''
                #!/usr/bin/env bash
                set -euo pipefail
                which home-manager

                # shellcheck disable=SC2046 # Intended splitting of OPTIONS
                read -ra options <<<"''${1:-.}"
                home-manager switch --flake "''${options[@]}" |& nom
              '';
            };
          };
        };
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      flake = {
        knownHosts = {
          "desktop.local" = ''
            desktop.local ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCjzYEuKtErq3irlOePfFj9tcbMSEp8Jkto1GnxQGJeyBwymwJ10THsN4Nidmpz/jne6GtxmXqzhq2577SImhjeN/FTid04js7EZ//vIXn9P0gJ4L70bAQzn1741l5Hg4ChD4h+hYkNh81HIKt59Es4+YA8QG1ktRStftFv/ks5dFQnVXlfapYsJpvxd4AhiyfQu5DdQoo8rPa8ReWQWb9B+CIV4N1ytfaqya3EMuLCJRCwjgDAgz9tDJDIiTSOqHgxtBRP5HGUVCFNXusMgHseVCzl5J5evOl+ZlVtONuxWMwS2uiyIbMXCZvi9qukEN7ukajfAbFFAowaLD9yz9WixLuxG6/Q3IlHJ07z9f4aNr15hLGysNNswGimNqfbBhIwxdc1H1tKUUZTbxNSFWnoOYBokvBQd/a+S1cVr1FmHXn0gbmFeJtCueJyrEHV7pgfxqDmWc3QaeLPhXlHj1WUzTVNcwUzCsRj0kPBNwClR/s9/9ayYexnRoj0i4HnmG/tTLtQEi/IuXiBAkPrTcpouPY83vvhAHUUFMaUXABidX8aIXgxIxnG/afUzGP2YwqSF8yjxIVoZXf+ZdZrT42AJC94/QuU5c48p96Pzd7Luoabt6tfJPx4RH8efGvR8aA1R6NXCbxEoXrPYORIbAyiRugvVxD7eFKc+CQULXcE3w==
            desktop.local ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHA6aLV48Q1ga/cKaWavmBOuNmV60YP4Au/2PmbNZZlF
          '';
          "github.com" = ''
            github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
            github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
            github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
          '';
          "gitlab.com" = ''
            gitlab.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Yt0aGROY5qX2UKSeOvuP4D6TPqKF1onrSzH9bx9XUf2lEdWT/ia1NEKjunUqu1xOB/StKDHMoX4/OKyIzuS0q/T1zOATthvasJFoPrAjkohTyaDUz2LN5JoH839hViyEG82yB+MjcFV5MU3N1l1QL3cVUCh93xSaua1N85qivl+siMkPGbO5xR/En4iEY6K2XPASUEMaieWVNTRCtJ4S8H+9
            gitlab.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=
            gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf
          '';
        };
        keys = {
        };
        defaultKeys = {
          "github.com" =
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDDDi6qJg5OogDltfP/moQSc35an6xT+3N7JpIO36ct+LBcwJ0FydXO7OFceTxKQh4Pztm4VY3Odlk8M8VLaBuPac4Au//GjUFtU1aYmYgraEpzVwkRtla6VP7wLp0bHihtHNUVfvFCBnhGfz066qNck7k6ntJwXGqWeedtdjMZrhA0HQHsJDbgi12sFyY2aizuzNgBK3I0hHvTYG+ApD8nCbQjukxY6DpMjdwPLkLcCuvvbYeVGie6EuztXlqxpI1aM8vMnTKXn6wUmbvOYeBGONe4qzNiRy+Z453AK6k0tqVxgWWnPvgAcMIO1DvY5a8LaEvI5MDSvrqPJyYRIqMOcQThIvubb1CbMpkgOcEmYfrUOFZOHtOIZDEzahS3ggLMkAb3VWRlfRz+e0ESraQ+aMxUr0xNWpIeFz10xSRO6FZu0Qlu5+1dPMI7WNI190FyD+nqHedZYrSmHXpsaJ0YrUeUSu1DNpavVwtJ3e34fEWwzsZ36uf1Tcv8OCJNpAsXmkQHff77+GFk5O4tEyguAqtxJjvtFwJuh3BCyCHAvXyUNbB6qm/Wyr5sKiGEb/G9wpyS8cw/1FpgMsVw+v+e8GVdOz/zE/jYiVbHvDFkSE34LoSd+/mrHYkHlZeUsUQaAKeqLL/C/uR9XzoXbPV54IgKSN/gYfLsRyysKo6Txw==";
          "desktop.local" =
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDg1BjrrEL43KwRmH2e4xF7R7XjO3bvG2ysJ3lk0XKmAtvmMGgBcQYwS2Q1/0rLKtnFNoYQA2koPoxGzHgW7qSxY0ltMs6FIDwfSdpJCeMy+NiayL30Lqu2zaM3SFsDC8TeSWv3kZdPr+RY/gUELiYx8VR4ZNd//Ykuu5+/rckO5bkqaT8iC8WzouLYSpwecTb2kAvyj1mrBSQH1QHqcowlDPwqGyCKh1CMTlX/jxEUOPpBrxhVFBiFFVnUJC28Kr+ggq8V34PiS+N/+QD+mCx6w71BfzV4JLl3NTclYWbg8ngxFE5olIKwpL0YZz/0ViW35KNhlAbI3IMbVeZTLKfCVJwMsV8GDuxTX81ypJO3VAPpjUQJ/4VnURqe+8zjBYhFzYJQBU9quCtQQnx7rM/0eav9a0op405cwFrhDc2fcuoD4egwyplm3hgacCGLSmCCk7Y5xSjaeO5MQpSgnVl+kdBXeZnWX5NrTqdlWcuW898Ijd0SLzidURvFjUauuprpk2QvnPw9oJivpC1HjVvPkYClBFqLwrjTQWtAACiBaFVKvQKygqzYfWYPz4gqO8EZQIuz+YZz/TftAhMDDNh9auo0vA3AaIwd7U972wnzq7/WfNo2SUacZoUerhMJlpPhpV5H54St3S9lfcwTVbZiX7wFsUu8FsO7wBguSFV4yQ==";
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
          username = "znd4";
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
        homeConfigurationFactory =
          {
            system,
            username,
            hostname,
            stateVersion,
            seshClConfig ? { },
            certificateAuthorities ? [ ],
            knownHosts ? self.knownHosts,
            outputs ? self,
            defaultKeys ? self.defaultKeys,
            keys ? self.keys,
            extraModules ? [ ],
            extraSpecialArgs ? { },
          }:
          home-manager.lib.homeManagerConfiguration {
            pkgs = nixpkgs.legacyPackages.${system};
            extraSpecialArgs = {
              inherit
                outputs
                knownHosts
                inputs
                system
                username
                hostname
                stateVersion
                ;
              keys = defaultKeys // (keys."${hostname}" or { });
              certificateAuthority =
                if certificateAuthorities != [ ] then
                  (builtins.toFile "certificate-authority.pem" (
                    lib.strings.concatStringsSep "\n" certificateAuthorities
                  ))
                else
                  null;
              seshClConfig = {
                gitlabHosts = [ ];
                githubOrgs = [ ];
                parentDirectories = [ "~" ];
              }
              // seshClConfig;
            }
            // extraSpecialArgs;
            modules = [ self.homeModules.default ] ++ extraModules;
          };
        homeConfigurations = (
          builtins.listToAttrs (
            builtins.map
              (
                {
                  username,
                  hostname,
                  certificateAuthorities ? [ ],
                  system ? "x86_64-linux",
                  stateVersion ? "23.11",
                }:
                (lib.attrsets.nameValuePair "${username}@${hostname}" (
                  self.homeConfigurationFactory {
                    inherit
                      stateVersion
                      system
                      username
                      hostname
                      certificateAuthorities
                      ;
                  }
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
                {
                  username = "znd4";
                  hostname = "work";
                  system = "aarch64-darwin";
                  stateVersion = "24.11";
                }
                {
                  username = "znd4";
                  hostname = "mac-mini";
                  system = "aarch64-darwin";
                  stateVersion = "24.11";
                }
              ]
          )
        );
      };
    };
}
