{
  pkgs,
  lib,
  outputs,
  ...
}:
{
  home.packages = with pkgs; [
    monaspace
    (nerdfonts.override {
      fonts = [
        "Monaspace"
        # Hello, what's up with you?
      ];
    })
  ];
  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        opacity = 0.9;
        option_as_alt = lib.mkIf (pkgs.system == "aarch64-darwin") "Both";
      };
      shell = {
        program = "${pkgs.fish}/bin/fish";
      };
      keyboard = {
        bindings = [
          {
            key = "+";
            mods = "Super";
            action = "IncreaseFontSize";
          }
          {
            key = "=";
            mods = "Super";
            action = "IncreaseFontSize";
          }
          {
            key = "NumpadAdd";
            mods = "Super";
            action = "IncreaseFontSize";
          }
          {
            key = "-";
            mods = "Super";
            action = "DecreaseFontSize";
          }
          {
            key = "NumpadSubtract";
            mods = "Super";
            action = "DecreaseFontSize";
          }
        ];
      };
      font = {
        normal = {
          family = "MonaspiceAr Nerd Font";
          # family = "MonaspiceNe Nerd Font";
          style = "Medium";
        };
        bold = {
          family = "MonaspiceXe Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "MonaspiceRn Nerd Font";
          style = "Italic";
        };
      };
    };
  };
}
