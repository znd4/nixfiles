# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  outputs,
  username,
  lib,
  config,
  osConfig,
  knownHosts,
  pkgs,
  stateVersion,
  keys,
  certificateAuthority,
  ...
}@args:
let
  authSocks = {
    x86_64-linux = "${config.home.homeDirectory}/.1password/agent.sock";
    aarch64-linux = "${config.home.homeDirectory}/.1password/agent.sock";
    aarch64-darwin = "${config.home.homeDirectory}/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";

  };
  dotConfig = "${inputs.self}/dotfiles/xdg-config/.config";
  system = pkgs.stdenv.system;
  personal_python = inputs.nixpkgs.legacyPackages.${system}.python3.withPackages (
    ps:
    # personal_python = inputs.nixpkgs-main.legacyPackages.${system}.python3.withPackages (ps:
    with ps; [
      ipython
      pipx
    ]
  );
  shellAliases =
    let
      ipython = "${personal_python}/bin/ipython --TerminalInteractiveShell.editing_mode=vi";
    in
    {
      nix = "NO_COLOR=1 command nix";
      bathelp = "bat -l help";
      awsume = ". awsume";
      kvalid = "kubeconform -summary -verbose -ignore-missing-schemas -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' -schema-location default";
      ipython = ipython;
      ipy = ipython;
      bh = "bat -l help";
      g = "git";
      by = "bat -l yaml";
      vi = "nvim";
      terraform = "tofu";
      openai = "op plugin run -- openai";
    };
  fishAliases = {
    awsume = "source (which awsume.fish)";
  };
  envMap = {
    # Add hardcoded environment variables here
  }
  // (lib.attrsets.optionalAttrs (certificateAuthority != null) {
    NODE_EXTRA_CA_CERTS = certificateAuthority;
    REQUESTS_CA_BUNDLE = certificateAuthority;
    SSL_CERT_FILE = certificateAuthority;
  });
in
{
  imports = [
    ./darwin
    ./nixos
    ./programs
    inputs.git-town-znd4.homeManagerModules.default
  ];

  nix.package = pkgs.nix;
  home.packages = [
    personal_python
  ];

  nixpkgs = {
    # You can add overlays here

    overlays = (import ./overlays args) ++ [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      # outputs.overlays.additions
      # outputs.overlays.modifications
      # outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default
      inputs.nil.overlays.nil

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
      outputs.overlays.default
      (final: prev: {
        sesh = (
          pkgs.buildGoModule rec {
            pname = "sesh";
            version = "2.7.1-znd4";

            src = inputs.sesh;

            vendorHash = "sha256-a45P6yt93l0CnL5mrOotQmE/1r0unjoToXqSJ+spimg=";

            ldflags = [
              "-s"
              "-w"
            ];

            meta = {
              description = "Smart session manager for the terminal";
              homepage = "https://github.com/joshmedeski/sesh";
              changelog = "https://github.com/joshmedeski/sesh/releases/tag/${src.rev}";
              license = lib.licenses.mit;
              maintainers = with lib.maintainers; [ gwg313 ];
              mainProgram = "sesh";
            };
          }
        );
      })
    ];
    # Configure your nixpkgs instance
    config = import ./nixpkgs-config.nix;
  };

  programs.git-town = {
    enable = true;
    enableAllAliases = true;
  };
  programs.ripgrep = {
    enable = true;
    arguments = [
      "--smart-case"
      "--hidden"
      "--glob=!.git/*"
    ];
  };
  # TODO: Enable saved WIFI connection credentials
  programs.atuin.enable = true;
  programs.atuin.enableFishIntegration = true;
  programs.atuin.enableNushellIntegration = false;
  programs.awscli = {
    enable = true;
    package = inputs.nixpkgs.legacyPackages.${system}.awscli2;
  };
  programs.gh = {
    enable = true;
    extensions = with pkgs; [
      gh-dash
      (buildGoModule {
        src = "${inputs.gh-s}";
        name = "gh-s";
        pname = "gh-s";
        vendorHash = "sha256-5UJAgsPND6WrOZZ5PUZNdwd7/0NPdhD1SaZJzZ+2VvM=";
      })
      (stdenv.mkDerivation {
        name = "gh-f";
        pname = "gh-f";
        src = inputs.gh-f;
        installPhase = ''
          mkdir -p $out/bin
          cp gh-f $out/bin
        '';
      })
    ];
    gitCredentialHelper.enable = false;
  };

  programs.gh-dash.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    OP_PLUGIN_ALIASES_SOURCED = 1;
  };
  home.username = username;

  xdg.configFile =
    let
      getFiles =
        dir: prefix:
        builtins.listToAttrs (
          map (fp: {
            name = dir + "/" + fp;
            value = {
              source = "${prefix}/${dir}/${fp}";
            };
          }) (builtins.attrNames (builtins.readDir "${prefix}/${dir}"))
        );
    in
    lib.foldl' lib.attrsets.recursiveUpdate { } [
      { "nixpkgs/config.nix".source = ./nixpkgs-config.nix; }
      (getFiles "fish/conf.d" "${inputs.self}/dotfiles/fish/.config")
      (getFiles "fish/completions" "${inputs.self}/dotfiles/fish/.config")
      (getFiles "fish/functions" "${inputs.self}/dotfiles/fish/.config")
      (lib.attrsets.genAttrs
        [
          "starship.toml"
          "direnv/direnvrc"
          "ptpython/config.py"
        ]
        (name: {
          source = "${dotConfig}/${name}";
        })
      )
    ];

  programs.ssh = {
    addKeysToAgent = "confirm";
    enable = true;
    userKnownHostsFile = "${
      (pkgs.writeText "known_hosts" (
        builtins.concatStringsSep "\n" (lib.attrsets.mapAttrsToList (name: value: value) knownHosts)
      ))
    }";
    extraConfig = "IdentityAgent ${authSocks.${system}}";

    matchBlocks = (
      lib.attrsets.mapAttrs (name: value: {
        identitiesOnly = true;
        identityFile = "${pkgs.writeText "${name}_id_rsa.pub" value}";
      }) keys
    );
  };

  # Add stuff for your user as you see fit:

  programs.skim =
    let
      fdCommand = "fd --type f --hidden --no-ignore-vcs --exclude .git";
    in
    {
      enable = true;
      defaultCommand = fdCommand;
      enableFishIntegration = false;
      fileWidgetCommand = fdCommand;
      changeDirWidgetCommand = "fd --type d --hidden --exclude '.git'";
      defaultOptions = [ "--cycle" ];
    };

  programs.zsh = {
    enable = true;
    plugins = [
      {
        name = "zsh-vi-mode";
        src = pkgs.fetchFromGitHub {
          owner = "jeffreytse";
          repo = "zsh-vi-mode";
          rev = "v0.11.0";
          sha256 = "sha256-xbchXJTFWeABTwq6h4KWLh+EvydDrDzcY9AQVK65RS8=";
        };
      }
    ];
    initExtra = ''
      setopt interactivecomments
    '';
    sessionVariables = envMap;
  };
  programs.bash = {
    enable = true;
    sessionVariables = envMap;
  };
  # Enable home-manager and git
  programs.fzf = {
    enable = true;
    enableFishIntegration = false;
    enableBashIntegration = false;
    enableZshIntegration = false;
  };
  programs.nushell = {
    enable = true;
    envFile.source = "${dotConfig}/nushell/env.nu";
    configFile.source = "${dotConfig}/nushell/config.nu";
    shellAliases = shellAliases;
    environmentVariables = envMap;
  };
  programs.man.generateCaches = true;
  programs.fish = {
    enable = true;
    functions = {
      flump = ''
        for file in $argv
            # Check if the argument is a regular file before trying to read it.
            if test -f "$file"
                echo "---- $file ----"
                cat "$file"
            end
        end
      '';

    };
    plugins = [
      {
        name = "fish-completion-sync";
        src = pkgs.fetchFromGitHub {
          owner = "pfgray";
          repo = "fish-completion-sync";
          rev = "ba70b6457228af520751eab48430b1b995e3e0e2";
          sha256 = "sha256-JdOLsZZ1VFRv7zA2i/QEZ1eovOym/Wccn0SJyhiP9hI=";
        };
      }
      {
        name = "fzf.fish";
        src = pkgs.fetchFromGitHub {
          owner = "PatrickF1";
          repo = "fzf.fish";
          rev = "8920367cf85eee5218cc25a11e209d46e2591e7a"; # v10.3
          sha256 = "sha256-T8KYLA/r/gOKvAivKRoeqIwE2pINlxFQtZJHpOy9GMM=";
        };
      }
    ];
    shellAbbrs = {
      bh = "bat -l help";
      dc = "docker compose";
      g = "git";
      gl = "glab";
      gt = "git-town";
      gc = "git commit";
      gd = "git diff";
      gpl = "git pull";
      gps = "git push";
      gs = "git status";
      fly = "flyctl";
      hm = "home-manager switch --flake .";
      j = "just";
      k = "kubectl";
      kk = "k9s";
      kr = "kubectl --context rancher-desktop";
      ky = "kubectl get -o yaml";
      n = "nvim -c 'Telescope oldfiles'";
      nfl = "nix flake update --commit-lock-file";
      pc = "pre-commit";
      tg = "terragrunt";
    };
    shellAliases = shellAliases // fishAliases;
    shellInit = lib.strings.concatStringsSep "\n" (
      [
        # put hard-coded init configuration in here
      ]
      ++ (lib.attrsets.mapAttrsToList (name: value: "set -gx ${name} ${value}") envMap)
    );
    functions = {
      fish_vi_cursor = {
        onVariable = "fish_bind_mode";
        body = ''
          switch $fish_bind_mode
              case default
                  echo -en "\e[2 q" # block cursor
              case insert
                  echo -en "\e[6 q" # line cursor
              case visual
                  echo -en "\e[2 q" # block cursor
          end
        '';
      };
    };
    interactiveShellInit = ''
      fish_vi_key_bindings
      # Use fzf.fish for C-t instead of raw fzf
      fzf_configure_bindings --directory=\ct
      set fzf_fd_opts --hidden --exclude .git
      ${pkgs.uv}/bin/uv generate-shell-completion fish | source
      set -g SHELL ${pkgs.fish}/bin/fish
      abbr -a by --position anywhere --set-cursor "% | bat -l yaml"
      ${pkgs.fnm}/bin/fnm env --use-on-cd --shell fish | source
      set -gx fish_complete_path $fish_complete_path ${config.home.profileDirectory}/share/fish/vendor_completions.d
      set --unpath JSONNET_PATH
    ''
    + (
      (if system == "aarch64-darwin" then "" else "\nset -q SSH_AUTH_SOCK")
      + "\nset -g SSH_AUTH_SOCK ${authSocks.${system}}"
    );
  };

  programs.starship = {
    enable = true;
  };
  programs.zoxide.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = stateVersion;
}
