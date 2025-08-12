{ config, ... }:
{
  programs.zk.enable = true;
  programs.zk.settings = {
    notebook.dir = "${config.home.homeDirectory}/Documents";
  };
}
