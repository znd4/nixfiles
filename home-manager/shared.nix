# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs, username, lib, config, pkgs, stateVersion, ... }: {

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

      "git/" = {
        recursive = false;
        source = "${dotConfig}/git/";
      };
    }
  ];

  programs.git = {
    enable = true;
    lfs.enable = true;
  };

  # Add stuff for your user as you see fit:
  home.packages = with pkgs; [
    # kmonad
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
    podman-compose
    pre-commit
    python-launcher
    ripgrep
    ruff
    rustc
    skim
    (buildGoModule {
      src = "${inputs.sesh}";
      name = "sesh";
      vendorHash = "sha256-zt1/gE4bVj+3yr9n0kT2FMYMEmiooy3k1lQ77rN6sTk=";
    })

    stow
    stylua
    terragrunt
    thefuck
    unzip
    wget
    xh
    zig
    zoxide
    zsh
    (python3.withPackages (ps: with ps; [ pre-commit ]))
    (buildEnv {
      name = "myScripts";
      paths = [ "${inputs.dotfiles}/scripts/.local" ];
    })
  ];

  programs.skim.enable = true;
  programs.zsh.enable = true;
  # Enable home-manager and git
  programs.fzf = {
    enable = true;
    tmux.enableShellIntegration = true;
  };
  programs.home-manager.enable = true;
  programs.fish = {
    enable = true;
    # plugins = [
    # {
    #     name = "fzf-fish";
    #   src = pkgs.fetchFromGithub{owner="patrickf1"; repo="fzf.fish";};
    # }
    # ];
    shellAbbrs = { ky = "kubectl get -o yaml"; };
    shellAliases = {
      nix = "NO_COLOR=1 command nix";
      bathelp = "bat -l help";
      bh = "bat -l help";
      g = "git";
      by = "bat -l yaml";
      k = "kubectl";
      vi = "nvim";
    };
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

    extraConfigBeforePlugins = ''
      set -g @sessionx-bind 'o'
      set -g @thumbs-command 'echo -n {} | cb copy && tmux display-message "Copied to clipboard"'
    '';

    plugins = with pkgs.tmuxPlugins; [
      battery
      catppuccin
      pain-control
      sensible
      tmux-fzf
      tmux-thumbs
    ];
    shortcut = "a";
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = stateVersion;
}
