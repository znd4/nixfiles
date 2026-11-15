# This repo's pre-commit hooks, from cachix/git-hooks.nix. Each hook's tool
# comes from nixpkgs, so a hook needs nothing installed on the machine.
#
# - `nix develop` writes .pre-commit-config.yaml (a symlink into the store,
#   git-ignored) and installs the git hook.
# - `nix flake check` runs the same hooks on a clean copy of the repo
#   (checks.<system>.pre-commit).
#
# To add a hook: enable one of git-hooks.nix's built-in hooks, or add an
# attribute to `hooks` with an `entry` (see `options-doc` below).
{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];

  perSystem =
    { config, pkgs, ... }:
    {
      pre-commit.settings.hooks = {
        nixfmt.enable = true;

        # docs/options.md is generated from the znd4.* option declarations.
        # Regenerate it, and fail the commit (so the new file can be staged)
        # when it changed. About 3-8 s.
        options-doc = {
          enable = true;
          name = "regenerate docs/options.md";
          entry = toString (
            pkgs.writeShellScript "options-doc" ''
              # In `nix flake check` this runs in the build sandbox, where
              # there is no nix to build with. checks.options-doc does the
              # same comparison there.
              if [ -n "''${NIX_BUILD_TOP:-}" ]; then exit 0; fi
              out=$(nix build --no-link --print-out-paths .#znd4-options-doc) || exit 1
              if ! ${pkgs.diffutils}/bin/cmp -s "$out" docs/options.md; then
                install -m 644 "$out" docs/options.md
                echo "docs/options.md was out of date; regenerated it, stage it and commit again"
                exit 1
              fi
            ''
          );
          files = "\\.nix$";
          pass_filenames = false;
        };
      };

      checks.options-doc = pkgs.runCommand "options-doc-up-to-date" { } ''
        if ! ${pkgs.diffutils}/bin/diff -u ${../docs/options.md} ${config.packages.znd4-options-doc}; then
          echo "docs/options.md is out of date: run the pre-commit hooks (nix develop -c pre-commit run options-doc)"
          exit 1
        fi
        touch $out
      '';

      devShells.default = pkgs.mkShell {
        shellHook = config.pre-commit.installationScript;
        packages = config.pre-commit.settings.enabledPackages;
      };
    };
}
