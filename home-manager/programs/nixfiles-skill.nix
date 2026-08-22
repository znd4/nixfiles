{ ... }:
{
  # Agent skill documenting how to contribute to this repo.
  home.file.".claude/skills/nixfiles" = {
    source = ../claude-skills/nixfiles;
    recursive = true;
  };
}
