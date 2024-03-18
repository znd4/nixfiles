# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  username,
  lib,
  config,
  osConfig,
  pkgs,
  stateVersion,
  keys,
  ...
}:
let
  system = pkgs.stdenv.system;
  shellAliases = {
    nix = "NO_COLOR=1 command nix";
    bathelp = "bat -l help";
    bh = "bat -l help";
    g = "git";
    by = "bat -l yaml";
    k = "kubectl";
    vi = "nvim";
    terraform = "tofu";
    openai = "op plugin run -- openai";
    gh = lib.mkDefault "op plugin run -- gh";
  };
  fishAliases = {
    awsume = "source (pyenv which awsume.fish)";
  };
in
{
  imports = [
    ./darwin
    ./nixos
    ./programs
  ];

  nix.package = pkgs.nix;

  nixpkgs = {
    # You can add overlays here
    overlays = [
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
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
      # Workaround for https://github.com/nix-community/home-manager/issues/2942
      allowUnfreePredicate = _: true;
    };
  };

  programs.ripgrep = {
    enable = true;
    arguments = [ "--smart-case" ];
  };
  # TODO: store wi-fi credentials
  # programs.jujutsu.enable = true; # TODO - try this out
  programs.thefuck.enable = true;
  programs.awscli.enable = true;
  programs.gh = {
    enable = true;
    extensions = with pkgs; [ gh-dash ];
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
      dotConfig = "${inputs.dotfiles}/xdg-config/.config";
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
      (getFiles "fish/conf.d" "${inputs.dotfiles}/fish/.config")
      (getFiles "fish/completions" "${inputs.dotfiles}/fish/.config")
      (getFiles "fish/functions" "${inputs.dotfiles}/fish/.config")
      {
        # "fish/"={source= "${inputs.dotfiles}/fish/.config/fish/"; enable=false;};
        "starship.toml".source = "${dotConfig}/starship.toml";
        # "direnv/direnvrc".source = "${dotConfig}/direnv/direnvrc";
        "direnv/direnvrc".text = builtins.readFile "${dotConfig}/direnv/direnvrc";
      }
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
    extraConfig = {
      pager = {
        diff = "delta";
        log = "delta";
        reflog = "delta";
      };
      user.signingKey = keys."github.com";
      init.defaultBranch = "main";
      commit.template = "${pkgs.writeText "commit-template" (
        builtins.readFile "${inputs.dotfiles}/xdg-config/.config/git/stCommitMsg"
      )}";
      commit.gpgSign = true;
      gpg.format = "ssh";
      push.autoSetupRemote = true;
      pull.rebase = false;
      credential.helper = [
        "cache --timeout 7200"
        "oauth"
      ];
      url = {
        # "ssh://git@github.com/".insteadOf = [
        #   "https://github.com/"
        #   "github:"
        #   "gh:"
        # ];
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
      sessionx = inputs.sessionx.packages.${system}.default;
      sesh = (
        buildGoModule {
          src = "${inputs.sesh}";
          name = "sesh";
          vendorHash = "sha256-zt1/gE4bVj+3yr9n0kT2FMYMEmiooy3k1lQ77rN6sTk=";
        }
      );
      personal_python = (python3.withPackages (ps: with ps; [ pre-commit ]));
      personal_scripts = (
        buildEnv {
          name = "myScripts";
          paths = [ "${inputs.dotfiles}/scripts/.local" ];
        }
      );
    in
    [
      # kmonad
      age
      asdf
      awsume
      bat
      bottom
      broot
      cargo
      clipboard-jh # TODO: install latest
      delta
      fd
      gcc
      git
      git-credential-oauth
      gnumake
      go
      google-cloud-sdk
      htop
      jc
      jq
      just
      kubectl
      nixfmt
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
      stow
      stylua
      talosctl
      terraform
      terragrunt
      thefuck
      unzip
      uv
      vale
      wget
      xh
      zenith
      zig
      zoxide
      zsh
    ];

  programs.skim.enable = true;
  programs.zsh.enable = true;
  # Enable home-manager and git
  programs.fzf = {
    enable = true;
  };
  programs.home-manager.enable = true;
  programs.nushell = {
    shellAliases = shellAliases;
    enable = true;
  };
  programs.fish = {
    enable = true;
    # plugins = [
    # {
    #     name = "fzf-fish";
    #   src = pkgs.fetchFromGithub{owner="patrickf1"; repo="fzf.fish";};
    # }
    # ];
    shellAbbrs = {
      ky = "kubectl get -o yaml";
      tg = "terragrunt";
      hm = "home-manager switch --flake .";
      j = "just";
      nfl = "nix flake update --commit-lock-file";
    };
    shellAliases = shellAliases // fishAliases;
    interactiveShellInit = ''
      fish_vi_key_bindings
      ${pkgs.uv}/bin/uv generate-shell-completion fish | source
    '';
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
