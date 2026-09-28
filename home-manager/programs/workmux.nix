# Personal workmux configuration. ../modules/workmux.nix defines the options.
{ inputs, lib, system, ... }:
{
  programs.workmux = {
    enable = true;
    package = inputs.workmux.packages.${system}.default;

    settings = {
      nerdfont = true;
      # Relative to the repo root. Ignored globally in git.nix.
      worktree_dir = ".worktrees";
    };

    # The prefix is C-a. Upstream recommends C-s for the dashboard and L for
    # last-done. tmux-resurrect uses prefix C-s (save) and pain-control uses
    # prefix L (resize), so the dashboard moves to C-d and last-done to C-l.
    # mkDefault lets a downstream flake (panw-nixfiles) change or null a key.
    tmuxIntegration.bindings = lib.mapAttrs (_: lib.mkDefault) {
      "C-d" = ''display-popup -h 30 -w 100 -E "workmux dashboard"'';
      "C-w" = ''display-popup -h 30 -w 100 -E "workmux dashboard --tab worktrees"'';
      "C-t" = ''run-shell "workmux sidebar"'';
      "C-l" = ''run-shell "workmux last-done"'';
      "Tab" = ''run-shell "workmux last-agent"'';
    };

    claudeCode.hooks.enable = true;
  };
}
