# glab ships a release most weeks and nixpkgs trails it by several versions, so
# take the packaging from `nixpkgs-glab` (see the comment on that input) and
# point the source at the latest upstream release.
#
# To bump: set `version` below, then build twice and paste the hashes nix
# reports — the src hash first, then vendorHash:
#
#   nix build --impure --no-link --expr 'let f = builtins.getFlake (toString ./.); \
#     s = builtins.currentSystem; o = n: import ./home-manager/overlays/${n}.nix \
#       { inherit (f) inputs; system = s; }; in \
#     ((f.inputs.nixpkgs.legacyPackages.${s}.extend (o "go")).extend (o "glab")).glab'
#
# glab's go.mod tracks the newest Go patch release, usually ahead of what the
# pin carries, so it builds with one from ./go.nix. If the build fails with
# "go.mod requires go >= X", add X there and point `buildGoModule` at it.
{ inputs, system, ... }:
(final: prev: {
  glab =
    let
      version = "1.125.0";
      pinned = inputs.nixpkgs-glab.legacyPackages.${system};
    in
    (pinned.glab.override { buildGoModule = final.buildGo1_27_3Module; }).overrideAttrs (_: {
      inherit version;
      src = pinned.fetchFromGitLab {
        owner = "gitlab-org";
        repo = "cli";
        tag = "v${version}";
        hash = "sha256-/9C44TQhya22OTf/2qfRpBsISCgo15QfOET5c0QIiR8=";
        # The build stamps the short commit into `glab --version`.
        leaveDotGit = true;
        postFetch = ''
          cd "$out"
          git rev-parse --short HEAD > $out/COMMIT
          find "$out" -name .git -print0 | xargs -0 rm -rf
        '';
      };
      vendorHash = "sha256-4YiqHUwLzwBrO7msIO039cTrirE1v443WWq+nYVPp6I=";
      ldflags = [
        "-s"
        "-w"
        "-X main.version=${version}"
      ];
      # The cmd/glab suite ends in a goleak check that finds a live HTTP
      # writeLoop goroutine in the Nix sandbox and fails the whole package. The
      # install-time versionCheckHook still proves the binary runs.
      doCheck = false;
    });
})
