{ pkgs, ... }:
let
  # GTD Flow (an Obsidian plugin) from the terminal: fuzzy-pick a perspective or
  # tag, list next actions, capture to the inbox. See ../bin/gtd.sh.
  #
  # It goes through the Obsidian CLI, which has to be switched on in the app
  # (Settings > General > Advanced > Command line interface), and Obsidian must
  # be running. The CLI ships with the app, so it isn't pinned here.
  gtd = pkgs.writeShellApplication {
    name = "gtd";
    runtimeInputs = with pkgs; [
      fzf
      jq
      coreutils
    ];
    text = builtins.readFile ../bin/gtd.sh;
  };
in
{
  home.packages = [ gtd ];
}
