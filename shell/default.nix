{ lib, config, pkgs, ... }: {

  programs.direnv = {
    enable = true;
  };
  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [ tmux-thumbs pain-control sensible catppuccin ];
    shortcut = "screen-256color";
  };
  programs.fish.enable = lib.mkDefault true;
  programs.starship.enable = true;
  programs.skim = {
    enable = true;
    fuzzyCompletion = true;
  };


  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withPython3 = true;
    withNodeJs = true;
  };
  programs.git = {
    enable = true;
    config = [
      {
        init.defaultBranch = "main";
        user = {
          name = "Zane Dufour";
          email = "zane@znd4.dev";
        };
        push.autoSetupRemote = true;
        pull.rebase = false;
      }
      {
        alias = {
          a = "add";
          pl = "pull";
          c = "commit";
          cm = "commit";
          co = "checkout";
          ck = "checkout";
          s = "status";
          ps = "push";
          d = "diff";
        };
      }
      # delta configuration
      {
        core = {
          pager = "delta";
        };
        interactive = {
          diffFilter = "delta --color-only";
        };
        delta = {
          pager = "less";
          navigate = true;
          light = false;
          side-by-side = true;
        };
        pager = {
          diff = "delta";
          log = "delta";
          reflog = "delta";
        };
        diff = {
          colorMoved = "default";
          pager = "delta";
        };
      }
    ];

  };
  environment.systemPackages = with pkgs; [
    asdf
    bat
    broot
    cargo
    delta
    fd
    gcc
    gh
    gnumake
    go
    htop
    just
    lazygit
    nodejs
    opam
    python-launcher
    python3
    ripgrep
    rustc
    stow
    stylua
    thefuck
    unzip
    wget
    zig
    zoxide
    zsh
  ];
}
