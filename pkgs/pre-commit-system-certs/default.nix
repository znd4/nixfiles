{ pkgs, ... }:

pkgs.writeShellScriptBin "pre-commit" ''
  exec ${pkgs.uv}/bin/uv tool run --from pre-commit --with pip-system-certs pre-commit "$@"
''
