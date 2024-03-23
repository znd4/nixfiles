{
  pkgs,
  lib,
  outputs,
  ...
}: {
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
