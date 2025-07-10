# Jujutsu configuration with tokyonight-storm theme
# Documentation: https://github.com/jj-vcs/jj/blob/main/docs/config.md
{ inputs, system, ... }:
{
  programs.jujutsu.enable = true;
  programs.jujutsu.package = inputs.nixos-unstable.legacyPackages.${system}.jujutsu;
  programs.jujutsu.settings = {
    user = {
      email = "zane@znd4.dev";
      name = "Zane Dufour";
    };

    # TokyoNight Storm theme colors to match ghostty configuration
    colors = {
      # Commit and change IDs
      commit_id = "#7aa2f7";  # tokyonight blue
      change_id = "#bb9af7";  # tokyonight magenta
      
      # Working copy highlighting
      "working_copy commit_id" = { fg = "#7aa2f7"; bold = true; };
      "working_copy change_id" = { fg = "#bb9af7"; bold = true; };
      
      # Diff colors
      "diff added" = "#9ece6a";    # tokyonight green
      "diff removed" = "#f7768e";  # tokyonight red
      "diff modified" = "#e0af68"; # tokyonight yellow
      
      # Enhanced diff tokens
      "diff added token" = { bg = "#1f2335"; fg = "#9ece6a"; };
      "diff removed token" = { bg = "#1f2335"; fg = "#f7768e"; };
      
      # Branch and bookmark colors
      branch = "#7dcfff";     # tokyonight cyan
      bookmark = "#ff9e64";   # tokyonight orange
      
      # Text and background
      default = "#c0caf5";    # tokyonight foreground
      description = "#a9b1d6"; # tokyonight dark foreground
      
      # Status indicators
      conflict = "#f7768e";    # tokyonight red
      "conflict marker" = { fg = "#f7768e"; bold = true; };
      
      # Email and author
      email = "#7dcfff";      # tokyonight cyan
      author = "#bb9af7";     # tokyonight magenta
      
      # Timestamps
      timestamp = "#a9b1d6";  # tokyonight dark foreground
    };

    ui = {
      # Use color-words diff for better readability
      diff-format = ":color-words";
      # Enable colors
      color = "auto";
    };
  };
}
