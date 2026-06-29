{
  pkgs,
  lib,
  ...
}:
let
  # `hunk` itself is provided on PATH by programs.hunk (see hunkdiff.nix), so it
  # is intentionally not pinned here — that keeps this tool buildable on every
  # system the hunkdiff flake may or may not target.
  hunk-mr = pkgs.writeShellApplication {
    name = "hunk-mr";
    runtimeInputs = with pkgs; [
      git
      gh
      glab
      jq
      gum
      coreutils
    ];
    text = builtins.readFile ../bin/hunk-mr.sh;
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
  home.packages = [ hunk-mr ];
  home.file = mkSkillFiles ../claude-skills/hunk-mr ".claude/skills/hunk-mr";
}
