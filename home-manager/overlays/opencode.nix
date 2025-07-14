{
  pkgs,
  ...
}:
(final: prev: {
  opencode = pkgs.writeShellScriptBin "opencode" ''
    GEMINI_API_KEY=$(op item get fjytwiisowht2tvbh6nlpdmlwm --fields credential --reveal) ${prev.opencode}/bin/opencode "$@"
  '';
})