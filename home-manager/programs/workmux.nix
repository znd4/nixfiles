# Personal workmux configuration. ../modules/workmux.nix defines the options.
{ inputs, lib, pkgs, system, ... }:
let
  # Sets the Claude session name to the workmux handle. Panes start in the
  # worktree, and the worktree directory name is the handle (the branch
  # slug). The tmux window name is the icon prefix plus the handle.
  claudeNamed = pkgs.writeShellScript "workmux-claude" ''
    exec claude -n "$(basename "$PWD")" "$@"
  '';
in
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
      # type = claude keeps the built-in workmux Claude support: prompt
      # injection and the continue/resume flags.
      agent = "claude-named";
      agents.claude-named = {
        type = "claude";
        command = "${claudeNamed}";
      };
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
