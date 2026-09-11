{ config, ... }:
{
  programs.zk.enable = true;
  programs.zk.settings = {
    # The notebook, not the whole Documents folder — pointing at ~/Documents
    # made zk index every unrelated file in it.
    notebook.dir = "${config.home.homeDirectory}/Documents/obsidian-gtd-main";
  };
}
