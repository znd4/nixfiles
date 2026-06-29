{ inputs, lib, pkgs, ... }:
let
  skillSrc = "${inputs.claude-skills-bendrucker}/plugins/git-town/skills/git-town";
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
  home.packages = [ pkgs.claude-code ];
  home.file = mkSkillFiles skillSrc ".claude/skills/git-town";
}
