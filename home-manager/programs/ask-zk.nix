{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.ask-zk;

  # The queue CLI. ../bin/ask-zk.py is a PEP 723 script with a PyPI dependency
  # (textual), so it runs through `uv run --script` -- same pattern as
  # herdr-mr-review in herdr.nix. Scripts without dependencies use pkgs.python3
  # directly (see herdr-snapshot.nix).
  #
  # ASK_NOTEBOOK is a default, not a forced value: a one-off invocation can
  # still point the CLI at another notebook.
  askZk = pkgs.writeShellApplication {
    name = "ask-zk";
    runtimeInputs = with pkgs; [
      uv
      zk
      coreutils
    ];
    text = ''
      export ASK_NOTEBOOK="''${ASK_NOTEBOOK:-${cfg.notebook}}"
      export ASK_STALE_DAYS="''${ASK_STALE_DAYS:-${toString cfg.staleDays}}"
      exec uv run --script ${../bin/ask-zk.py} "$@"
    '';
  };

  # The Claude Code status line. It scans note files with awk instead of
  # calling ask-zk, because it runs on every assistant message. uv start-up
  # costs ~123 ms; awk costs ~62 ms.
  #
  # bashOptions drops `errexit` deliberately. The script survives failing
  # commands: `[ -n "$BRANCH" ] && line1+=...` returns non-zero when the
  # directory is not a git repo, and `set -e` would exit before the queue row
  # prints.
  claudeStatusline = pkgs.writeShellApplication {
    name = "claude-statusline";
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    runtimeInputs = with pkgs; [
      jq
      git
      gawk
      coreutils
    ];
    text = ''
      export ASK_NOTEBOOK="''${ASK_NOTEBOOK:-${cfg.notebook}}"
      export ASK_STALE_DAYS="''${ASK_STALE_DAYS:-${toString cfg.staleDays}}"
      ${builtins.readFile ../bin/claude-statusline.sh}
    '';
  };

  # Install the agent skill into ~/.claude/skills/, mirroring claude-code.nix.
  mkSkillFiles =
    dir: prefix:
    let
      entries = builtins.readDir dir;
    in
    lib.concatMapAttrs (
      name: type:
      if type == "regular" then
        { "${prefix}/${name}".source = "${dir}/${name}"; }
      else if type == "directory" then
        mkSkillFiles "${dir}/${name}" "${prefix}/${name}"
      else
        { }
    ) entries;
in
{
  options.programs.ask-zk = {
    notebook = lib.mkOption {
      type = lib.types.str;
      default = config.programs.zk.settings.notebook.dir or "${config.home.homeDirectory}/notes";
      defaultText = lib.literalExpression "config.programs.zk.settings.notebook.dir";
      example = "/home/alice/work-notes";
      description = ''
        Notebook directory that holds the queue (one markdown note per item).

        This is the single source of the path. Both `ask-zk` and the status
        line receive it as `ASK_NOTEBOOK`, so they always read the same
        notebook.

        `ZK_NOTEBOOK_DIR` is deliberately not used. `zk` lets cwd
        auto-discovery override that variable, so an agent inside a different
        notebook would write items to the wrong place.
      '';
    };

    staleDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7;
      description = ''
        Age (in days) at which an open item counts as stale. The status-line
        badge turns red when any item exceeds this age, and `ask-zk count`
        exits 3.
      '';
    };
  };

  config = {
    home.packages = [
      askZk
      claudeStatusline
    ];

    home.file = {
      # settings.json points statusLine at this path, and several skills call
      # ~/.claude/bin/ask-zk by absolute path. Both stay valid as symlinks into
      # the store, so nothing outside Nix has to be edited.
      ".claude/statusline.sh".source = "${claudeStatusline}/bin/claude-statusline";
      ".claude/bin/ask-zk".source = "${askZk}/bin/ask-zk";
    }
    // (mkSkillFiles ../claude-skills/ask-zk ".claude/skills/ask-zk");
  };
}
