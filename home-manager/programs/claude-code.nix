{ inputs, ... }:
{
  home.file.".claude/skills/git-town" = {
    source = "${inputs.claude-skills-bendrucker}/plugins/git-town/skills/git-town";
    recursive = true;
  };
}
