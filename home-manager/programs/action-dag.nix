{
  config,
  pkgs,
  lib,
  ...
}:
let
  # The action-graph CLI (see ../claude-skills/action-dag/SKILL.md).
  # ../bin/action-dag.py is a PEP 723 script (https://peps.python.org/pep-0723/)
  # with PyPI dependencies (pyyaml, markdown-it-py), so it runs through
  # `uv run --script`, the same way as ask-zk in ask-zk.nix.
  #
  # The graphs are in the ask-zk notebook, next to their hub notes.
  # The environment can override ACTION_DAG_NOTEBOOK and ACTION_DAG_TEMPLATE.
  #
  # glab, ask-zk and the probe commands (gcloud, ...) come from the user's PATH.
  # This file does not pin them: glab must use the user's own login, and a
  # probe can call any tool.
  #
  # Tests: uv run --script home-manager/bin/tests/test_action_dag.py
  actionDag = pkgs.writeShellApplication {
    name = "action-dag";
    runtimeInputs = with pkgs; [
      uv
      coreutils
    ];
    text = ''
      export ACTION_DAG_NOTEBOOK="''${ACTION_DAG_NOTEBOOK:-${config.programs.ask-zk.notebook}}"
      export ACTION_DAG_TEMPLATE="''${ACTION_DAG_TEMPLATE:-${../bin/action-dag.template.html}}"
      exec uv run --script ${../bin/action-dag.py} "$@"
    '';
  };

  # Install the agent skill into ~/.claude/skills/action-dag/, the same way as
  # claude-code.nix.
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
  home.packages = [ actionDag ];
  home.file = mkSkillFiles ../claude-skills/action-dag ".claude/skills/action-dag";
}
