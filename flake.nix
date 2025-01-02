{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixvim.url = "github:nix-community/nixvim";
    ghostty = {
      url = "github:ghostty-org/ghostty";
    };
    ghostty-hm-module.url = "github:znd4/ghostty-hm-module";
    # nixpkgs.url = nixos_unstable_url;
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11-small";
    git-town-znd4.url = "github:znd4/git-town/home-manager";
    nixpkgs-trunk.url = "github:NixOS/nixpkgs/master";
    nixpkgs-24_11.url = "github:NixOS/nixpkgs/nixos-24.11-small";

    nil.url = "github:oxalica/nil";
    nixd = {
      url = "github:nix-community/nixd";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      # url = "github:hyprwm/Hyprland";
      type = "github";
      owner = "hyprwm";
      repo = "Hyprland";
      ref = "v0.38.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    xdg-config = {
      url = "github:znd4/xdg-config";
      flake = false;
    };

    # waybar.url = "github:Alexays/Waybar";
    # waybar.inputs.nixpkgs.follows = "nixpkgs";

    hyprland-plugins.url = "github:hyprwm/hyprland-plugins";
    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs.nixpkgs.follows = "nixpkgs";
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
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kmonad = {
      url = "git+https://github.com/kmonad/kmonad?submodules=1&dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    miryoku_kmonad = {
      url = "github:znd4/miryoku_kmonad/add-nix-support";
      inputs.kmonad.follows = "kmonad";
    };
  };

  # inputs.kmonad = {
  #   url = "github:kmonad/kmonad";
  #   flake = false;
  # };
  # inputs.kmonad.inputs.nixpkgs.follows = "nixpkgs";

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
      ];
      perSystem =
        {
          config,
          pkgs,
          ...
        }:
        {
          formatter = pkgs.nixfmt-rfc-style;
          overlayAttrs = {
            inherit (config.packages) telescope-filter;
          };
          packages = (import ./pkgs { inherit pkgs inputs; }) // {
            telescope-filter = (
              pkgs.writeShellApplication (
                let
                  nvim_temp = inputs.nixvim.legacyPackages.${pkgs.system}.makeNixvim {
                    plugins = {
                      web-devicons.enable = true;
                      telescope = {
                        enable = true;
                        settings = {
                          defaults = {
                            mappings =
                              let
                                new_enter = {
                                  __raw = ''
                                    function(prompt_bufnr)
                                      local entry = require('telescope.actions.state').get_selected_entry()
                                      vim.print({"selected_entry", entry})
                                      vim.fn.writefile({ entry.value }, vim.g.search_output_file )
                                      require("telescope.actions").close(prompt_bufnr)
                                      vim.cmd.quit()
                                    end
                                  '';
                                };
                              in
                              {
                                i = {
                                  "<cr>" = new_enter;
                                };
                                n = {
                                  "<cr>" = new_enter;
                                };
                              };
                            layout_config = {
                              horizontal = {
                                height = 0.99;
                                width = 0.99;
                              };
                              vertical = {
                                height = 0.99;
                                width = 0.99;
                              };
                            };
                          };
                        };
                      };
                    };
                  };
                  script = pkgs.writeText "lua-script" (
                    builtins.readFile "${inputs.self}/scripts/telescope-filter.lua"
                  );
                in
                {
                  name = "telescope-filter";
                  runtimeInputs = [
                    nvim_temp
                    script
                  ];
                  text = ''
                    #!/usr/bin/env bash
                    set -euo pipefail
                    # set -x
                    input=$(mktemp)
                    cat - > "$input"
                    output=$(mktemp)
                    if [ ! -t 0 ]; then
                      ${nvim_temp}/bin/nvim \
                        -c "let g:search_output_file='$output'" \
                        -c "let g:search_input_file='$input'" \
                        -c "lua assert(loadfile('${script}'))()" \
                        < /dev/tty > /dev/tty
                    fi

                    cat "$output"
                  '';
                }
              )
            );
            nixos-rebuild-switch = pkgs.writeShellApplication {
              name = "nixos-rebuild-switch";
              runtimeInputs = with pkgs; [
                expect
                nix-output-monitor
              ];
              text = ''
                #!/usr/bin/env bash
                which nix-darwin
                sudo unbuffer nixos-rebuild switch --flake "''${1:-.}" |& nom
              '';
            };
            nix-darwin-switch = pkgs.writeShellApplication {
              name = "nix-darwin-switch";
              runtimeInputs = with pkgs; [
                expect
                darwin.packages.${pkgs.system}.default
                nix-output-monitor
              ];
              text = ''
                #!/usr/bin/env bash
                which nix-darwin
                unbuffer nix-darwin switch --flake "''${1:-.}" |& nom
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
                which home-manager
                unbuffer home-manager switch --flake "''${1:-.}" |& nom
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
        };
        keys = {
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
            knownHosts ? self.knownHosts,
            outputs ? self,
            keys ? self.keys,
            extraModules ? [ ],
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
                  stateVersion ? "23.11",
                }:
                (lib.attrsets.nameValuePair "${username}@${hostname}" (
                  self.homeConfigurationFactory {
                    inherit
                      stateVersion
                      system
                      username
                      hostname
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
              ]
          )
        );
      };
    };
}
