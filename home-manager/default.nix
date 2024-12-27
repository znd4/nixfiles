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
  ...
}@args:
let
  authSocks = {
    x86_64-linux = "${config.home.homeDirectory}/.1password/agent.sock";
    aarch64-linux = "${config.home.homeDirectory}/.1password/agent.sock";
    aarch64-darwin = "\"${config.home.homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
  };
  dotConfig = "${inputs.self}/dotfiles/xdg-config/.config";
  system = pkgs.stdenv.system;
  shellAliases =
    let
      ipython = "ipython --TerminalInteractiveShell.editing_mode=vi";
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
      gh = lib.mkDefault "op plugin run -- gh";
    };
  fishAliases = {
    awsume = "source (which awsume.fish)";
  };
in
{
  imports = [
    ./darwin
    ./nixos
    ./programs
    inputs.git-town-znd4.homeManagerModules.default
  ];

  nix.package = pkgs.nix;

  nixpkgs = {
    # You can add overlays here

    overlays = (import ./overlays args) ++ [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      # outputs.overlays.additions
      # outputs.overlays.modifications
      # outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default
      # inputs.kmonad.overlays.default
      inputs.nil.overlays.nil

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
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
  programs.jujutsu.enable = true; # TODO - try this out
  programs.jujutsu.package = inputs.nixos-unstable.legacyPackages.${system}.jujutsu;
  programs.thefuck = {
    enable = true;
  };
  programs.awscli = {
    enable = true;
    package = inputs.nixpkgs-24_11.legacyPackages.${system}.awscli2;
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

  programs.lazygit = {
    enable = true;
    settings = {
      gui.nerdFontsVersion = 3;
      git.autoFetch = false;
    };
  };

  programs.git = {
    enable = true;
    lfs.enable = true;

    userName = "Zane Dufour";
    userEmail = "zane@znd4.dev";
    delta = {
      enable = true;
      options = {
        pager = "less";
      };
    };
    signing = {
      signByDefault = true;
      key = "${pkgs.writeText "github.com_id_rsa.pub" keys."github.com"}";
    };
    extraConfig = {
      pager = {
        diff = "delta";
        log = "delta";
        reflog = "delta";
      };

      # Configure commit signing with my ssh key
      gpg.format = "ssh";
      # TODO - configure this differently on MacOS
      gpg.ssh.program =
        if system == "aarch64-darwin" then
          "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
        else
          "${pkgs._1password-gui}/bin/op-ssh-sign";
      user.signingKey = "${pkgs.writeText "github.com_id_rsa.pub" keys."github.com"}";

      init.defaultBranch = "main";
      commit.template = "${pkgs.writeText "commit-template" (
        builtins.readFile "${inputs.self}/dotfiles/xdg-config/.config/git/stCommitMsg"
      )}";
      commit.gpgSign = true;
      push.autoSetupRemote = true;
      pull.rebase = false;
      # credential.helper = [
      #   "cache --timeout 7200"
      #   "oauth"
      # ];
      url = {
        "ssh://git@github.com/".insteadOf = [
          "https://github.com/"
          "github:"
          "gh:"
        ];
      };
    };
    aliases = {
      a = "add";
      pl = "pull";
      c = "commit";
      cm = "commit";
      co = "checkout";
      s = "status";
      ps = "push";
      d = "diff";
      cedit = "config --global --edit";
      undo-last-commit = "reset HEAD~1";
      config-edit = "config --global --edit";
      new-branch = "checkout -b";
      conflicted = "!nvim +Conflicted";
      cb = "branch --show-current";
      root = "!pwd";
      findall = ''
        !f() { echo -e "
        Found in refs:
        "; git for-each-ref refs/ | grep $1; echo -e "
        Found in commit messages:
        "; git log --all --oneline --grep="$1"; echo -e "
        Found in commit contents:
        "; git log --all --oneline -S "$1"; }; f'';
    };
  };
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
  home.packages =
    with pkgs;
    let
      akuity = inputs.self.packages.${system}.akuity;
      argocd = inputs.nixos-unstable.legacyPackages.${system}.argocd;
      sessionx = inputs.sessionx.packages.${system}.default;
      jujutsu = inputs.nixos-unstable.legacyPackages.${system}.jujutsu;
      spacectl = inputs.nixpkgs-trunk.legacyPackages.${system}.spacectl;
      personal_python = inputs.nixpkgs-24_11.legacyPackages.${system}.python3.withPackages (
        ps:
        # personal_python = inputs.nixpkgs-main.legacyPackages.${system}.python3.withPackages (ps:
        with ps; [
          ipython
          pipx
        ]
      );
      personal_scripts = (
        buildEnv {
          name = "myScripts";
          paths = [ "${inputs.self}/dotfiles/scripts/.local" ];
        }
      );
    in
    [
      # kmonad
      age
      alejandra
      akuity
      argocd
      asdf
      awsume
      bat
      bottom
      broot
      cargo
      clipboard-jh
      cobra-cli
      cue
      delta
      devbox
      devenv
      fd
      fnm
      gcc
      git
      git-credential-oauth
      git-open
      git-town
      glab
      glow
      gnumake
      (google-cloud-sdk.withExtraComponents (
        with google-cloud-sdk.components;
        [
          gke-gcloud-auth-plugin
        ]
      ))
      gum
      helmfile
      home-manager
      htop
      jc
      jq
      just
      kubectl
      kubernetes-helm
      nixfmt-rfc-style
      nodejs
      opam
      opentofu
      personal_python
      personal_scripts
      podman-compose
      pre-commit
      python-launcher
      ruff
      rustc
      sd
      sesh
      sessionx
      skim
      sops
      spacectl
      stow
      stylua
      talosctl
      terraform
      terraform-docs
      terragrunt
      thefuck
      unzip
      uv
      vale
      vulnix
      wget
      xh
      zenith
      # zig
      zoxide
      zsh
    ];

  programs.skim =
    let
      fdCommand = "fd --type f --hidden --no-ignore-vcs --exclude .git";
    in
    {
      enable = true;
      defaultCommand = fdCommand;
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
  };
  programs.bash.enable = true;
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
  };
  programs.man.generateCaches = true;
  programs.fish = {
    enable = true;
    # plugins = [
    # {
    #     name = "fzf-fish";
    #   src = pkgs.fetchFromGithub{owner="patrickf1"; repo="fzf.fish";};
    # }
    # ];
    shellAbbrs = {
      k = "kubectl";
      n = "nvim -c 'Telescope oldfiles'";
      ky = "kubectl get -o yaml";
      tg = "terragrunt";
      hm = "home-manager switch --flake .";
      j = "just";
      nfl = "nix flake update --commit-lock-file";
      g = "git";
      gt = "git-town";
      kk = "k9s";
      kr = "kubectl --context rancher-desktop";
      pc = "pre-commit";
    };
    shellAliases = shellAliases // fishAliases;
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
    interactiveShellInit =
      ''
        fish_vi_key_bindings
        ${pkgs.uv}/bin/uv generate-shell-completion fish | source
        set -g SHELL ${pkgs.fish}/bin/fish
        abbr -a by --position anywhere --set-cursor "% | bat -l yaml"
        abbr -a bh --position anywhere --set-cursor "% | bat -l help"
        ${pkgs.fnm}/bin/fnm env --use-on-cd --shell fish | source
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
  programs.k9s.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = stateVersion;
}
