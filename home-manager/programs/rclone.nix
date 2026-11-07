{
  config,
  pkgs,
  ...
}:
let
  # Wraps rclone instead of rebuilding it, so the binary cache still applies.
  # The wrapper fetches the rclone.conf encryption password from 1Password via
  # a store-path op, so op needn't be on PATH. --set-default lets either
  # variable be overridden per command.
  rclone = pkgs.symlinkJoin {
    name = "rclone-wrapped";
    paths = [ pkgs.rclone ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/rclone \
        --set-default RCLONE_PASSWORD_COMMAND "${pkgs._1password-cli}/bin/op read op://Private/rclone/password" \
        --set-default RCLONE_EXCLUDE_FROM "${config.xdg.configHome}/rclone/excludes.txt"
    '';
  };
in
{
  # Not programs.rclone: it regenerates rclone.conf on activation, which would
  # clobber the OAuth tokens that `rclone config create` wrote there.
  home.packages = [ rclone ];

  # Rebuildable cruft that shouldn't be copied to cloud storage. Applied to
  # every rclone command via RCLONE_EXCLUDE_FROM; pass --exclude-from /dev/null
  # to copy everything.
  xdg.configFile."rclone/excludes.txt".text = ''
    venv/**
    .venv/**
    .tox/**
    node_modules/**
    __pycache__/**
    .DS_Store
  '';
}
