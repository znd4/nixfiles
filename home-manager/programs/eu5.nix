{ ... }:
{
  # Agent skill for inspecting EU5 user data / saves on this machine.
  home.file.".claude/skills/eu5-files" = {
    source = ../claude-skills/eu5-files;
    recursive = true;
  };
}
