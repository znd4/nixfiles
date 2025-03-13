{ config, ... }:
{
  programs.k9s = {
    enable = true;
    settings = {
      k9s = {
        screenDumpDir = "${config.xdg.cacheHome}/k9s-screendumps/";
      };
    };
  };
}
