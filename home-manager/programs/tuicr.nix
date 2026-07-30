# tuicr — a review-first diff TUI (github.com/agavra/tuicr). This is the pane
# that alt+r opens on the right (see herdr.nix / ../bin/herdr-mr-review.py), and
# the reason it replaced hunk there: tuicr speaks to the forge, so comments made
# in the pane submit back to the PR/MR instead of only exporting as text.
#
# Three halves that have to stay in sync:
#
#   * the binary comes from nixpkgs (cached, no local Rust build) via the
#     `nixpkgs-tuicr` pin — `nixpkgs-unstable` predates tuicr, see flake.nix;
#   * the herdr wrapper, which upstream does not ship (tmux and zellij only); and
#   * the agent skill, which is just files at `skills/tuicr/` in the source tree
#     that the nixpkgs package does not install, hence the `tuicr-src` input.
#
# The nixpkgs package's `src` hash and the `tuicr-src` narHash are the same tree
# today (sha256-uLtwpieKBTbLLDmgE4LLNljvv69i0cBRvU1WEgy09Xo=), which is the
# property worth preserving: when bumping, move the `tuicr-src` tag to match
# whatever version the `nixpkgs-tuicr` rev carries, so the skill docs describe
# the installed binary.
#
# There is no upstream home-manager module (the flake exposes only
# `packages.default` and `devShells.default`, and nix-community/home-manager has
# no tuicr module), so the config file is written by hand.
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  system = pkgs.stdenv.system;
  tuicr = inputs.nixpkgs-tuicr.legacyPackages.${system}.tuicr;

  # Upstream ships wrappers for tmux and zellij only. This is the herdr one.
  #
  # `jujutsu` is intentionally absent from runtimeInputs even though the script
  # probes for `jj`: pinning it here dragged in jj 0.29 against the 0.35 in the
  # ambient profile, i.e. 75MB of closure to shadow the user's own newer jj.
  # The probe is already guarded by `command -v jj`, and writeShellApplication
  # only *prepends* to PATH, so the real one is found. Same call as `herdr`.
  tuicr-wrapper-herdr = pkgs.writeShellApplication {
    name = "tuicr-wrapper-herdr";
    runtimeInputs = [
      tuicr
      pkgs.coreutils
      pkgs.git
      pkgs.jq
    ];
    text = builtins.readFile ../bin/tuicr-wrapper-herdr.sh;
  };

  # Upstream's skills/tuicr, plus the herdr wrapper and the SKILL.md edits that
  # make an agent actually reach for it.
  #
  # Three of the edits use --replace-fail: the frontmatter description (what an
  # agent reads when deciding whether to load the skill at all), the launch
  # matrix, and the wrapper-path list. If upstream rewrites any of those, this
  # build breaks loudly at the next bump rather than silently shipping a skill
  # whose only documented launch paths are tmux and zellij — neither of which
  # exists on this machine. The three advisory-prose edits use --replace-warn;
  # they are more likely to get reworded upstream and losing one costs nothing.
  tuicr-skill = pkgs.runCommand "tuicr-skill-${tuicr.version}" { } ''
    cp -r ${inputs.tuicr-src}/skills/tuicr $out
    chmod -R u+w $out

    install -m 0755 ${lib.getExe tuicr-wrapper-herdr} $out/tuicr-wrapper-herdr.sh

    matrixOld=$(cat <<'EOF'
    | Environment | Action |
    |-------------|--------|
    | `$TMUX` is set | Run `tuicr-wrapper.sh /path/to/repo` |
    EOF
    )
    matrixNew=$(cat <<'EOF'
    | Environment | Action |
    |-------------|--------|
    | `$HERDR_ENV` is set | Run `tuicr-wrapper-herdr.sh /path/to/repo`. Pass `--no-wait` to open the pane and return immediately instead of blocking for the length of the review, then poll `tuicr review comments`. It prints the new pane id on stdout. The pane opens *unfocused*; only add `--focus` if the user just asked for the review pane and is expecting the jump. |
    | `$TMUX` is set | Run `tuicr-wrapper.sh /path/to/repo` |
    EOF
    )

    pathsOld=$(cat <<'EOF'
    <skill-directory>/tuicr-wrapper.sh /path/to/repo
    EOF
    )
    pathsNew=$(cat <<'EOF'
    <skill-directory>/tuicr-wrapper-herdr.sh /path/to/repo
    <skill-directory>/tuicr-wrapper.sh /path/to/repo
    EOF
    )

    ambiguityOld=$(cat <<'EOF'
    If both `$TMUX` and `$ZELLIJ` are set, prefer the innermost multiplexer if that
    is clear; otherwise ask.
    EOF
    )
    ambiguityNew=$(cat <<'EOF'
    Check `$HERDR_ENV` first. Some shell profiles export `WS_TMUX_SESSION_NAME`
    unconditionally, so a tmux-shaped guess under herdr will fail against a tmux
    server that is not running; `$TMUX` itself stays unset there. If both `$TMUX`
    and `$ZELLIJ` are set, prefer the innermost multiplexer if that is clear;
    otherwise ask.
    EOF
    )

    tipsOld=$(cat <<'EOF'
    ## Multiplexer Tips

    tmux:
    EOF
    )
    tipsNew=$(cat <<'EOF'
    ## Multiplexer Tips

    herdr:

    - Close tuicr: press `q`
    - Move between panes: `herdr pane focus --direction left|right|up|down`
    - Close the pane from outside: `herdr pane close <pane_id>`
    - Geometry: `TUICR_PANE_DIRECTION` (`right`/`down`) and `TUICR_PANE_RATIO`
    - Focus: off by default so the pane cannot grab the keyboard mid-keystroke.
      `--focus` / `TUICR_PANE_FOCUS=1` opts in.
    - Re-running the wrapper while tuicr is already up prints the existing pane
      id instead of opening a second one.

    tmux:
    EOF
    )

    substituteInPlace $out/SKILL.md \
      --replace-fail \
        'launch tuicr in tmux/zellij when a user needs an interactive review pane.' \
        'launch tuicr in herdr, tmux, or zellij when a user needs an interactive review pane.' \
      --replace-fail "$matrixOld" "$matrixNew" \
      --replace-fail "$pathsOld" "$pathsNew" \
      --replace-warn "$ambiguityOld" "$ambiguityNew" \
      --replace-warn "$tipsOld" "$tipsNew" \
      --replace-warn \
        '| No active session, tmux/zellij available |' \
        '| No active session, herdr/tmux/zellij available |'
  '';
in
{
  home.packages = [
    tuicr
    # Also shipped inside the skill directory; on PATH so it is usable by hand.
    tuicr-wrapper-herdr
  ];

  # ~/.config/tuicr/config.toml. Unknown keys are ignored with a startup
  # warning, so keep this to keys documented in upstream docs/CONFIG.md.
  xdg.configFile."tuicr/config.toml".text = ''
    # Managed by home-manager (home-manager/programs/tuicr.nix). Edit there.

    theme = "catppuccin-macchiato"

    # Match the side-by-side review style used with hunk.
    diff_view = "side-by-side"

    # Vi bindings in the comment box, to match the shell and editor. Toggle at
    # runtime with `:vim` if it gets in the way.
    comment_vim = true

    scroll_offset = 5

    # The binary is nix-managed and cannot self-update, so the startup check is
    # noise that can only ever tell us to go bump the flake.
    no_update_check = true

    # Stamped on comments authored in the TUI. Agents pass `--username` on
    # `tuicr review add` explicitly, so this is what distinguishes mine from
    # theirs; without it both sides fall back to the literal "user". Taken from
    # the host's own user so this stays right across machines (znd4 personally,
    # zdufour at work) rather than hardcoding one of them.
    username = "${config.home.username}"

    # Comments are UNTYPED unless this list exists, and `tuicr review add
    # --type` only accepts ids configured here. The skill's agent instructions
    # (SKILL.md "Use `--type issue` for problems by default", plus suggestion /
    # note / praise) therefore need exactly these four ids to have any effect —
    # keep the two in sync. The first entry is the default when you start
    # typing; `None` is always appended to the end of the Tab cycle.
    #
    # `definition` is not decoration: it is included in the `Comment types:`
    # legend of the exported markdown, i.e. it is what tells a downstream LLM
    # what each tag is supposed to mean.
    comment_types = [
      { id = "issue",      color = "red",    definition = "a problem that should be fixed before merge" },
      { id = "suggestion", color = "yellow", definition = "an optional improvement; author may decline" },
      { id = "note",       color = "blue",   definition = "context or observation, no action required" },
      { id = "praise",     color = "green",  definition = "positive feedback, no action required" },
    ]

    [forge]
    # Upstream default is true, which prepends `[ISSUE] ` etc. to the body of
    # every comment pushed to a real PR/MR. Off here: the classification is
    # only useful locally (TUI badges, and the `[TYPE]` tags + legend in the
    # `--stdout` markdown, both on separate code paths from this toggle), and
    # agent-authored comments already lead with the `🤖:` marker, so a second
    # prefix is chrome in front of every sentence a coworker reads.
    #
    # Caveat if this ever gets flipped back: the `false` branch is an early
    # return in `build_inline_body` (src/forge/submit.rs), so it also strips the
    # `File-level: ` marker from file-level comments.
    comment_type_prefix = false
  '';

  # Install the agent skill into ~/.claude/skills/tuicr.
  #
  # This does NOT use the recursive-readDir `mkSkillFiles` helper: that walks the
  # source with `builtins.readDir`, which works for a plain directory in the repo
  # but would be import-from-derivation here, since the skill is a build output
  # (upstream's tree + our SKILL.md patches). `recursive = true` gets the same
  # per-file symlink layout without evaluating the derivation at eval time.
  home.file.".claude/skills/tuicr" = {
    source = tuicr-skill;
    recursive = true;
  };
}
