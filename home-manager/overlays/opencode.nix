{
  pkgs,
  ...
}:
(final: prev: {
  opencode = prev.opencode.overrideAttrs (oldAttrs: {
    buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ prev.makeWrapper ];
    postInstall = ''
      ${oldAttrs.postInstall or ""}
      rm $out/bin/opencode
      makeWrapper ${prev.opencode}/bin/opencode $out/bin/opencode \
        --run 'export ANTHROPIC_API_KEY=$(op item get ubybp63edpezb5ilr2yr5reu5y --fields credential --reveal)'
    '';
  });
})
