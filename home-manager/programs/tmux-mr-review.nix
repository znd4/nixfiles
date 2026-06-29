{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.programs.tmux-mr-review;

  # `~` → `$HOME` so the script can expand it at runtime (Nix won't).
  workDir = builtins.replaceStrings [ "~" ] [ "$HOME" ] cfg.workDirectory;

  # The script lives in ../bin as plain bash (so it's shellcheck-clean and easy
  # to edit without Nix-string escaping); we read it in and prepend the one value
  # it needs from Nix. `hunk` itself is intentionally NOT in runtimeInputs — it's
  # provided on PATH by programs.hunk and the Hunk pane runs it from the user's
  # environment.
  script = pkgs.writeShellApplication {
    name = "tmux-mr-review";
    runtimeInputs = with pkgs; [
      git
      gum
      tmux
      fish
      coreutils
      gh
      glab
      jq
    ];
    text = ''
      export HUNK_MR_WORKDIR="${workDir}"
    ''
    + builtins.readFile ../bin/tmux-mr-review.sh;
  };
in
{
  options.programs.tmux-mr-review = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Popup to check out a GitHub PR / GitLab MR and review it in Hunk.";
    };

    keybinding = mkOption {
      type = types.str;
      default = "M-r";
      description = "Tmux keybinding (used with -n, so no prefix) for the review popup.";
    };

    workDirectory = mkOption {
      type = types.str;
      default = "~/Work";
      description = "Root where repos are cloned (<workDir>/<host>/<project>).";
    };
  };

  config = mkIf cfg.enable {
    # -n binds without the prefix (Alt-r by default); -E closes the popup when
    # the script exits. The popup is sized for clone/fetch output, not just the
    # one-line prompt.
    programs.tmux.extraConfig = ''
      bind -n ${cfg.keybinding} display-popup -E -w 80% -h 60% "${script}/bin/tmux-mr-review"
    '';
  };
}
