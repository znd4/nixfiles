# glab ships a release most weeks and nixpkgs trails it by several versions, so
# take the packaging from `nixpkgs-glab` (see the comment on that input) and
# point the source at the latest upstream release.
#
# To bump: set `version` below, then build twice and paste the hashes nix
# reports — the src hash first, then vendorHash:
#
#   nix build --impure --no-link --expr 'let f = builtins.getFlake (toString ./.); \
#     p = f.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}; in \
#     (p.extend (import ./home-manager/overlays/glab.nix { inherit (f) inputs; \
#       system = builtins.currentSystem; })).glab'
{ inputs, system, ... }:
(final: prev: {
  glab =
    let
      version = "1.115.0";
      pinned = inputs.nixpkgs-glab.legacyPackages.${system};
    in
    pinned.glab.overrideAttrs (_: {
      inherit version;
      src = pinned.fetchFromGitLab {
        owner = "gitlab-org";
        repo = "cli";
        tag = "v${version}";
        hash = "sha256-LIPT/5YLj+VWytBox0iB7JFaJkWtWwtrhWS1gN4t5qw=";
        # The build stamps the short commit into `glab --version`.
        leaveDotGit = true;
        postFetch = ''
          cd "$out"
          git rev-parse --short HEAD > $out/COMMIT
          find "$out" -name .git -print0 | xargs -0 rm -rf
        '';
      };
      vendorHash = "sha256-7l3iFKVykOUSRbRe/eqwmQUIFakvkK0PEvY//gtV+gI=";
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
