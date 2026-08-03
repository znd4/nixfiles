# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  pkgs,
  keys,
  certificateAuthority,
  lib,
  _1password_ssh,
  ...
}:
let
  system = pkgs.stdenv.system;
in
{
  programs.git = {
    enable = true;
    lfs.enable = true;

    userName = "Zane Dufour";
    userEmail = "zane@znd4.dev";
    ignores = [
      "**/.claude/settings.local.json"
      ".zn-work"
      ".jj"
    ];
    delta = {
      # enable = true;
      options = {
        pager = "less";
      };
    };
    signing = {
      signByDefault = true;
      key = "${pkgs.writeText "github.com_id_rsa.pub" keys."github.com"}";
    };
    extraConfig = {
      # pager = {
      #   diff = "delta";
      #   log = "delta";
      #   reflog = "delta";
      # };
      core.longPaths = true;

      # Configure commit signing with my ssh key
      #     [gpg "ssh"]
      # program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
      gpg.ssh.program = lib.optional _1password_ssh "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      gpg.format = "ssh";
      # TODO - configure this differently on MacOS
      user.signingKey = keys."github.com";

      init.defaultBranch = "main";
      commit.template = "${pkgs.writeText "commit-template" (
        builtins.readFile "${inputs.self}/dotfiles/xdg-config/.config/git/stCommitMsg"
      )}";
      commit.gpgSign = true;
      push.autoSetupRemote = true;
      # Push to the tracked upstream even when the local branch name differs
      # from the remote branch name (e.g. local `mr-353` -> `origin/docs/...`).
      # Avoids the default `simple` refusing to push on a name mismatch.
      push.default = "upstream";
      # Only auto-track a start point when the new branch shares its name.
      # git's default (`true`) tracks *any* remote-tracking start point, so
      # `git worktree add -b feat/foo <dir> origin/main` silently sets
      # feat/foo's upstream to origin/main -- and with `push.default = upstream`
      # above, a bare `git push` from that worktree then aims at main.
      # `simple` makes that case set no upstream at all. Anything that really
      # does want a cross-name upstream (herdr-mr-review's `mr-N` ->
      # `origin/<source-branch>`) sets it explicitly with `--set-upstream-to`,
      # which bypasses this setting entirely.
      branch.autoSetupMerge = "simple";

      git-town.sync-feature-strategy = "rebase";

      pull.rebase = true;
      # credential.helper = [
      #   "cache --timeout 7200"
      #   "oauth"
      # ];
      url = {
        "git@github.com:protectai".insteadOf = [
          "https://github.com/protectai"
        ];
        "git@github.com:znd4".insteadOf = [
          "https://github.com/znd4"
        ];
      };
    };
    extraConfig.http.sslCAInfo = lib.mkIf (certificateAuthority != null) certificateAuthority;
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
    };
  };
}
