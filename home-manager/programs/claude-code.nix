{ inputs, lib, ... }:
let
  skillSrc = "${inputs.claude-skills-bendrucker}/plugins/git-town/skills/git-town";
  jjSkillSrc = "${inputs.jujutsu-workflow-skill}/skills/jujutsu-workflow";
  mkSkillFiles = dir: prefix:
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
  # Note: the claude-code CLI is intentionally NOT installed here. The nixpkgs
  # package lags upstream; the auto-updating ~/.local/bin/claude is used instead.
  # This module only provides agent skill files.
  home.file =
    (mkSkillFiles skillSrc ".claude/skills/git-town")
    # Jujutsu (jj) agentic workflow skill. Pinned via the flake input; the two
    # scripts under scripts/ carry their 0755 mode from the git source.
    // (mkSkillFiles jjSkillSrc ".claude/skills/jujutsu-workflow");
}
