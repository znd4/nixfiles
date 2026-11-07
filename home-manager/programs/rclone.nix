{
  config,
  pkgs,
  ...
}:
{
  # Not programs.rclone: it regenerates rclone.conf on activation, which would
  # clobber the OAuth tokens that `rclone config create` wrote there.
  home.packages = [ pkgs.rclone ];

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
  home.sessionVariables.RCLONE_EXCLUDE_FROM = "${config.xdg.configHome}/rclone/excludes.txt";
}
