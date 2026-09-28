# Personal workmux configuration. ../modules/workmux.nix defines the options.
{ inputs, lib, system, ... }:
{
  programs.workmux = {
    enable = true;
    # No checks: in the darwin build sandbox, the test
    # socket_path_for_a_long_instance_can_be_bound fails because the build
    # directory makes the socket path longer than SUN_LEN. numtide/llm-agents.nix
    # disables the checks for the same package.
    package = inputs.workmux.packages.${system}.default.overrideAttrs { doCheck = false; };

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

    shellAlias = "wm";

    claudeCode.hooks.enable = true;
  };
}
