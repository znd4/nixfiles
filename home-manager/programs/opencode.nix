{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  home.packages = [ pkgs.opencode ];
  
  programs.git.ignores = [ ".opencode" ];
  # To check available models: curl -s https://models.dev/api.json | jq '.anthropic.models | keys[]'
  programs.fish.shellInit = ''
    set -gx OPENCODE_MODEL "anthropic/claude-sonnet-4-20250514"
  '';
  programs.zsh.sessionVariables.OPENCODE_MODEL = "anthropic/claude-sonnet-4-20250514";
  programs.bash.sessionVariables.OPENCODE_MODEL = "anthropic/claude-sonnet-4-20250514";
  xdg.configFile."opencode/opencode.json".source = "${inputs.self}/xdg-config/opencode/opencode.json";
}
