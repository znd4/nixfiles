{
  inputs = {
    hunkdiff = {
      url = "git+ssh://git@github.com/modem-dev/hunk.git?shallow=1";
    };
    # tuicr — review-first diff TUI, the review pane behind alt+r. Source-only
    # (flake = false): normally the *binary* comes from nixpkgs (see
    # nixpkgs-tuicr) and the only thing wanted from this tree is
    # `skills/tuicr/`. Evaluating upstream's flake would pull naersk,
    # flake-utils and a second nixpkgs-unstable into the lock for no benefit.
    # Keep the tag in sync with the tuicr version in nixpkgs-tuicr so the skill
    # docs match the binary.
    #
    # TEMPORARILY ON A FORK BRANCH, and therefore also the binary: while this
    # points at znd4/tuicr, tuicr.nix rebuilds the nixpkgs derivation from this
    # tree instead of using the cached one. The branch carries one commit on
    # top of upstream main —
    # <https://github.com/znd4/tuicr/commit/4908fe9> "fix(gitlab): return MR
    # commits oldest-first". `ForgeBackend::list_pull_request_commits` is
    # documented as chronological and GitHub/Bitbucket honour it, but the
    # GitLab backend returned `merge_requests/<n>/commits` verbatim and GitLab
    # serves that newest-first. `pr_range_sha_pair` then reads the selection's
    # parent off the inverted list and compares head→base, so narrowing a
    # GitLab MR to a subset of its commits draws the diff BACKWARDS — a file
    # the MR adds renders as a modification that strips its contents. Since
    # "commits since your last review" auto-narrows, alt+r hit this without
    # anyone touching the selector.
    #
    # Revert to `github:agavra/tuicr/v<version>` (and drop the src override in
    # tuicr.nix) once the fix is upstream and in a nixpkgs-tuicr rev.
    tuicr-src = {
      url = "github:znd4/tuicr/fix/gitlab-commit-order";
      flake = false;
    };
    # herdr — terminal agent multiplexer (ships its own flake). Normally pinned
    # to a release tag; bump deliberately. Its nixpkgs (unstable) is left to its
    # own pin so the vendored libghostty-vt zig deps resolve as upstream expects.
    #
    # The org moved ogulcancelik -> herdrdev in v0.8.0 (relicensed AGPL-3.0 ->
    # Apache-2.0 in the same release); the old path still redirects, but point
    # at the canonical one.
    #
    # TEMPORARILY OFF-TAG: this rev is master at the merge of
    # https://github.com/herdrdev/herdr/pull/2291 ("fix(input): keep pending url
    # clicks across host focus loss"), the fix for
    # https://github.com/herdrdev/herdr/issues/2290 — ctrl+clicking a link in a
    # Claude Code pane opened TWO browser tabs whenever the button was held long
    # enough for the browser to steal focus before release. herdr opened the URL
    # on press and then forwarded the same click to the pane, which opened it
    # again. It is labelled pending-release: not in v0.8.0 (tagged the day
    # before the merge) and not in any preview build either. A rev, not master:
    # this is a deliberate pin, so it does not drift.
    #
    # Go back to `ref=refs/tags/vX.Y.Z` as soon as a release carries the fix.
    # Note the crate version on this rev is still "0.8.0", so `herdr status`
    # cannot tell this build from the tag — herdr-handoff compares store paths
    # for exactly that reason (see programs/herdr.nix).
    herdr = {
      url = "git+ssh://git@github.com/herdrdev/herdr.git?shallow=1&rev=1997b88b3fa45f838d44e69dcebde8acf33899fc";
    };
    # herdr-thumbs plugin (tmux-thumbs for herdr). Extracted from the vendored
    # copy that used to live in home-manager/bin/herdr-thumbs/. Follows our
    # nixpkgs + herdr so the wrapped `herdr` on the launcher's PATH matches the
    # server we run.
    herdr-plugin-thumbs = {
      url = "git+ssh://git@github.com/znd4/herdr-plugin-thumbs.git?shallow=1&ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.herdr.follows = "herdr";
    };
    catppuccin-ghostty = {
      url = "git+ssh://git@github.com/catppuccin/ghostty.git?shallow=1";
      flake = false;
    };
    flake-parts.url = "git+ssh://git@github.com/hercules-ci/flake-parts.git?shallow=1";
    sesh = {
      url = "git+ssh://git@github.com/znd4/sesh.git?shallow=1&ref=main";
      flake = false;
    };
    ghostty = {
      url = "git+ssh://git@github.com/ghostty-org/ghostty.git?shallow=1";
    };
    dagger.url = "git+ssh://git@github.com/dagger/nix.git?shallow=1";
    dagger.inputs.nixpkgs.follows = "nixpkgs";

    ghostty-hm-module.url = "git+ssh://git@github.com/znd4/ghostty-hm-module.git?shallow=1";
    git-town-znd4.url = "git+ssh://git@github.com/znd4/git-town.git?shallow=1&ref=home-manager";

    home-manager = {
      url = "git+ssh://git@github.com/nix-community/home-manager.git?shallow=1&ref=release-25.11"; # Match your nixpkgs version
      inputs.nixpkgs.follows = "nixpkgs"; # Ensure it uses the same nixpkgs
    };

    # pre-commit.url = "git+ssh://git@github.com/znd4/nixpkgs.git?shallow=1&ref=feat/pre-commit/add-pip-system-certs";
    # nixpkgs.url = nixos_unstable_url;
    nixpkgs.url = "git+ssh://git@github.com/NixOS/nixpkgs.git?shallow=1&ref=nixos-25.11-small";
    nixpkgs-unstable.url = "git+ssh://git@github.com/NixOS/nixpkgs.git?shallow=1&ref=nixos-unstable";
    # nixpkgs-24_11.url = "github:NixOS/nixpkgs/nixos-24.11-small";
    nixpkgs-opencode.url = "git+ssh://git@github.com/NixOS/nixpkgs.git?shallow=1&rev=1f0f25154225df0302adcd7b8110ad2c99e48adc";
    # nixpkgs-git-town-21_1_0.url = "github:nixos/nixpkgs/pull/419405/head";
    nixpkgs-git-town-21_2_0.url = "git+ssh://git@github.com/znd4/nixpkgs.git?ref=git-town-21.2.0";
    # tuicr landed in nixpkgs long after the `nixpkgs-unstable` pin above, which
    # is why this gets its own rev rather than reading from that input: bumping
    # unstable repo-wide to reach one package would drag eight months of drift
    # through every other package that resolves from it. Same pattern as
    # nixpkgs-opencode. Keep the rev's tuicr version in sync with `tuicr-src`.
    nixpkgs-tuicr.url = "git+ssh://git@github.com/NixOS/nixpkgs.git?shallow=1&rev=624af665418d3c65d544145b4d34ad696439570e";
    # jj: `nixpkgs-unstable` above is pinned to 2025-11 and only carries jj
    # 0.35, while the jujutsu-workflow skill is written against 0.42+. Same
    # per-package-pin reasoning as nixpkgs-tuicr — and deliberately the *same
    # rev*, so this costs no extra fetch. That rev has jj 0.43.0 (latest
    # upstream release); bump it when a newer jj is wanted.
    nixpkgs-jujutsu.url = "git+ssh://git@github.com/NixOS/nixpkgs.git?shallow=1&rev=624af665418d3c65d544145b4d34ad696439570e";
    # television: `nixpkgs-unstable` above carries tv 0.13.5, which leaves the
    # preview panel on a stale entry when the query narrows the result list to
    # a different selection — you read one entry's preview while a different
    # one is selected. Fixed by 0.15.9. Same per-package-pin reasoning as
    # nixpkgs-tuicr, and deliberately the *same rev* as it and nixpkgs-jujutsu,
    # so this costs no extra fetch. That rev has tv 0.15.9 (latest upstream).
    nixpkgs-television.url = "git+ssh://git@github.com/NixOS/nixpkgs.git?shallow=1&rev=624af665418d3c65d544145b4d34ad696439570e";
    # glab: nixpkgs trails glab's weekly releases by several versions, and
    # `nixpkgs-unstable` above is pinned to 2025-11 and only carries 1.74. The
    # overlay overrides src to the latest upstream tag, so what this input
    # supplies is the *packaging* plus a Go new enough to build it — glab's
    # go.mod now asks for 1.26, which neither nixpkgs nor the unstable pin has.
    # Same per-package-pin reasoning as nixpkgs-tuicr, and deliberately the
    # *same rev* as it, nixpkgs-jujutsu and nixpkgs-television, so this costs no
    # extra fetch.
    nixpkgs-glab.url = "git+ssh://git@github.com/NixOS/nixpkgs.git?shallow=1&rev=624af665418d3c65d544145b4d34ad696439570e";

    nil.url = "git+ssh://git@github.com/oxalica/nil.git?shallow=1";
    nil.inputs.nixpkgs.follows = "nixpkgs";

    xdg-config = {
      url = "git+ssh://git@github.com/znd4/xdg-config.git?shallow=1";
      flake = false;
    };

    gh-s = {
      url = "git+ssh://git@github.com/gennaro-tedesco/gh-s.git?shallow=1";
      flake = false;
    };
    gh-f = {
      url = "git+ssh://git@github.com/gennaro-tedesco/gh-f.git?shallow=1";
      flake = false;
    };
    sessionx = {
      url = "git+ssh://git@github.com/omerxx/tmux-sessionx.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-skills-bendrucker = {
      url = "github:bendrucker/claude/1db049f4b21063bb7e18448851150fea5c98cd0e";
      flake = false;
    };
    # Jujutsu (jj) workflow skill for agentic coding. Pinned to a reviewed
    # commit (not a branch/tag) to avoid supply-chain drift; bump deliberately.
    jujutsu-workflow-skill = {
      url = "github:netresearch/jujutsu-workflow-skill/a22e4befb7639004698f8f63035e99bbe4a39ffd";
      flake = false;
    };
    # Pi coding agent — a terminal coding agent from pi.dev
    # (earendil-works/pi). Upstream ships no Nix, so this is lukasl-dev's
    # third-party packaging, which also carries the home-manager module.
    #
    # Pinned to a reviewed revision on purpose: an unpinned url would let a
    # `nix flake update` pull unreviewed code from an intermediary onto every
    # machine that follows this flake. It also drags in bun2nix, flake-parts
    # and jail.nix. Bump it deliberately, after reading the diff.
    #
    # It follows nixpkgs-unstable, not nixpkgs: the package needs
    # `typescript-go`, which stable does not carry. Downstream flakes such as
    # panw-nixfiles repoint our `nixpkgs` at a stable channel, so following
    # that one breaks the build for them and not for us.
    pi-coding-agent = {
      url = "github:lukasl-dev/pi.nix/92c057264e847c4676a80a5d57e968b5d25828a6";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    darwin = {
      url = "git+ssh://git@github.com/LnL7/nix-darwin.git?shallow=1&ref=nix-darwin-25.11";
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
                set -x

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
          "github.com" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkoZGPqvCciloARGk9/rgPdjCFI2JmsYbgboEv98RKc";
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
        darwinConfigurations."Zanes-MacBook-Neo.local" = self.darwinFactory {
          username = "znd4";
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
            _1password_ssh ? false,
            seshClConfig ? { },
            certificateAuthorities ? [ ],
            knownHosts ? self.knownHosts,
            outputs ? self,
            defaultKeys ? self.defaultKeys,
            keys ? self.keys,
            identityAgent ? null,
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
                identityAgent
                _1password_ssh
                ;
              keys = defaultKeys // (keys."${hostname}" or { });
              certificateAuthority =
                if certificateAuthorities != [ ] then
                  let
                    combinedCA = nixpkgs.legacyPackages.${system}.concatTextFile {
                      name = "ca-bundle-combined";
                      files = [
                        "${nixpkgs.legacyPackages.${system}.cacert}/etc/ssl/certs/ca-bundle.crt"
                        (builtins.toFile "custom-ca.pem" (lib.strings.concatStringsSep "\n" certificateAuthorities))
                      ];
                    };
                  in
                  "${combinedCA}"
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
                args:
                (lib.attrsets.nameValuePair "${args.username}@${args.hostname}" (
                  self.homeConfigurationFactory (
                    {
                      certificateAuthorities = [ ];
                      system = "x86_64-linux";
                      stateVersion = "23.11";
                    }
                    // args
                  )
                ))
              )
              [
                {
                  username = "znd4";
                  hostname = "Zanes-MacBook-Neo.local";
                  system = "aarch64-darwin";
                  identityAgent = ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
                  _1password_ssh = true;
                }
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
