{ pkgs, lib, ... }:
{
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    monaspace
    (nerdfonts.override {
      fonts = [
        "FiraCode"
        "VictorMono"
        "Monaspace"
        "NerdFontsSymbolsOnly"
      ];
    })
  ];
  programs.kitty = {
    enable = true;
    keybindings = {
      "ctrl+cmd+," = "load_config_file";
    };
    settings = {
      symbol_map = builtins.concatStringsSep " " [
        (builtins.concatStringsSep "," [
          "U+23FB-U+23FE"
          "U+2665"
          "U+26A1"
          "U+2B58"
          "U+E000-U+E00A"
          "U+E0A0-U+E0A3"
          "U+E0B0-U+E0C8"
          "U+E0CA"
          "U+E0CC-U+E0D2"
          "U+E0D4"
          "U+E200-U+E2A9"
          "U+E300-U+E3E3"
          "U+E5FA-U+E634"
          "U+E700-U+E7C5"
          "U+EA60-U+EBEB"
          "U+F000-U+F2E0"
          "U+F300-U+F32F"
          "U+F400-U+F4A9"
          "U+F500-U+F8FF"
        ])
        "Symbols Nerd Font Mono"
      ];
      italic_font = "MonaspiceRN NFM Italic";
      bold_italic_font = "MonaspiceRN NFM Bold Italic";
      # italic_font = "VictorMonoNerdFontPropo-Italic";
    };
    theme = "Tokyo Night"; # "Tokyo Night {Moon/Storm}"
    font = {
      package = pkgs.nerdfonts;
      name = "MonaspiceAr NFM";
    };
  };
}
