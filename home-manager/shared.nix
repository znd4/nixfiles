# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs, username, lib, config, pkgs, system, stateVersion, keys, ... }:
let
  shellAliases = {
    nix = "NO_COLOR=1 command nix";
    bathelp = "bat -l help";
    bh = "bat -l help";
    g = "git";
    by = "bat -l yaml";
    k = "kubectl";
    vi = "nvim";
  };
in {

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

  home.sessionVariables = { EDITOR = "nvim"; };
  home.username = username;

  xdg.configFile = let
    dotConfig = "${inputs.dotfiles}/xdg-config/.config";
    getFiles = dir: prefix:
      builtins.listToAttrs (map (fp: {
        name = dir + "/" + fp;
        value = { source = "${prefix}/${dir}/${fp}"; };
      }) (builtins.attrNames (builtins.readDir "${prefix}/${dir}")));
  in lib.foldl' lib.attrsets.recursiveUpdate { } [
    (getFiles "fish/conf.d" "${inputs.dotfiles}/fish/.config")
    (getFiles "fish/completions" "${inputs.dotfiles}/fish/.config")
    (getFiles "fish/functions" "${inputs.dotfiles}/fish/.config")
    {
      "nvim/" = {
        source = "${dotConfig}/nvim/";
        #recursive=true;
      };
      # "fish/"={source= "${inputs.dotfiles}/fish/.config/fish/"; enable=false;};
      "starship.toml".source = "${dotConfig}/starship.toml";
      "wezterm/wezterm.lua".source = "${dotConfig}/wezterm/wezterm.lua";
      # "direnv/direnvrc".source = "${dotConfig}/direnv/direnvrc";
      "direnv/direnvrc".text = builtins.readFile "${dotConfig}/direnv/direnvrc";

    }
  ];

  programs.git = {
    enable = true;
    lfs.enable = true;

    userName = "Zane Dufour";
    userEmail = "zane@znd4.dev";
    delta.enable = true;
    extraConfig = {
      user.signingKey = keys."github.com";
      init.defaultBranch = "main";
      commit.template = "${pkgs.writeText "commit-template" (builtins.readFile
        "${inputs.dotfiles}/xdg-config/.config/git/stCommitMsg")}";
      commit.gpgSign = true;
      gpg.format = "ssh";
      push.autoSetupRemote = true;
      pull.rebase = false;
      url = {
        "ssh://git@git2.company.com/".insteadOf = "https://git2.company.com/";
        "ssh://git@git.company.com/".insteadOf =
          "https://git.company.com/";
        "ssh://git@github.com/".insteadOf =
          [ "https://github.com/" "github:" "gh:" ];
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
    matchBlocks = {
      "github.com" = {
        identitiesOnly = true;
        identityFile =
          "${pkgs.writeText "github_id_rsa.pub" keys."github.com"}";
      };
    };
  };

  # Add stuff for your user as you see fit:
  home.packages = with pkgs;
    let
      sessionx = inputs.sessionx.packages.${system}.default;
      sesh = (buildGoModule {
        src = "${inputs.sesh}";
        name = "sesh";
        vendorHash = "sha256-zt1/gE4bVj+3yr9n0kT2FMYMEmiooy3k1lQ77rN6sTk=";
      });
      personal_python = (python3.withPackages (ps: with ps; [ pre-commit ]));
      personal_scripts = (buildEnv {
        name = "myScripts";
        paths = [ "${inputs.dotfiles}/scripts/.local" ];
      });
    in [
      # kmonad
      age
      asdf
      awscli2
      awsume
      bat
      broot
      cargo
      clipboard-jh
      delta
      fd
      gcc
      gh
      git
      gnumake
      go
      google-cloud-sdk
      htop
      just
      kubectl
      lazygit
      lua-language-server
      neovim
      neovim-remote
      nixfmt
      nodejs
      opam
      personal_python
      personal_scripts
      podman-compose
      pre-commit
      python-launcher
      ripgrep
      ruff
      rustc
      sesh
      sessionx
      skim
      sops
      stow
      stylua
      talosctl
      terragrunt
      thefuck
      unzip
      vale
      wget
      xh
      zig
      zoxide
      zsh
    ];

  programs.skim.enable = true;
  programs.zsh.enable = true;
  # Enable home-manager and git
  programs.fzf = {
    enable = true;
    tmux.enableShellIntegration = true;
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
    shellAbbrs = { ky = "kubectl get -o yaml"; };
    shellAliases = shellAliases;
    interactiveShellInit = ''
      fish_vi_key_bindings
    '';
  };

  programs.starship = { enable = true; };
  programs.zoxide.enable = true;
  programs.direnv.enable = true;
  programs.k9s.enable = true;

  programs.tmux = {
    disableConfirmationPrompt = true;
    enable = true;
    historyLimit = 10000;
    keyMode = "vi";
    mouse = true;
    shell = "${pkgs.fish}/bin/fish";
    terminal = "screen-256color";
    tmuxinator.enable = true;
    tmuxp.enable = true;
    extraConfig = ''
      bind-key "T" run-shell "sesh connect $(
        sesh list -tz | fzf-tmux -p 55%,60% \
        		--no-sort --border-label ' sesh ' --prompt '⚡  ' \
        		--header '  ^a all ^t tmux ^x zoxide ^f find' \
        		--bind 'tab:down,btab:up' \
        		--bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list)' \
        		--bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t)' \
        		--bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z)' \
        		--bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)'
      )"
      # vi mode
      bind P paste-buffer
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      unbind -T copy-mode-vi Enter
      bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel 'cb copy'
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'cb copy'
      bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'cb copy'

      unbind r
      bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded ~/.tmux.conf"

      # Turn the mouse on, but without copy mode dragging
      unbind -n MouseDrag1Pane
      unbind -Tcopy-mode MouseDrag1Pane

      # allow passthrough (e.g. for iterm image protocol)
      set-option -g allow-passthrough on
    '';

    plugins = with pkgs.tmuxPlugins; [
      battery
      catppuccin
      pain-control
      sensible
      tmux-fzf
      {
        plugin = tmux-thumbs;
        extraConfig = ''
          set -g @thumbs-command 'echo -n {} | cb copy && tmux display-message "Copied to clipboard"'
        '';
      }
      {
        plugin = inputs.sessionx.packages.${system}.default;
        extraConfig = ''
          set -g @sessionx-bind 'o'
        '';
      }
    ];
    shortcut = "a";
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = stateVersion;
}
