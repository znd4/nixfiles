{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.opencode ];
  
  programs.git.ignores = [ ".opencode" ];
  xdg.configFile."opencode/.opencode.json".text = builtins.toJSON {
    providers = {
      anthropic = {
        apiKey = "placeholder"; # Will be overridden by ANTHROPIC_API_KEY env var
      };
    };
    agents = {
      coder = {
        model = "claude-4-sonnet";
      };
    };
  };
}
