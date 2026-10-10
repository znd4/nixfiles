{ pkgs, ... }:
# Obsidian Sync without the desktop app: https://obsidian.md/help/sync/headless
# The npm tarball has no lockfile, so ./package-lock.json was generated with
# `npm install --package-lock-only` against the unpacked tarball. Regenerate it
# when bumping the version.
pkgs.buildNpmPackage rec {
  pname = "obsidian-headless";
  version = "0.0.14";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/obsidian-headless/-/obsidian-headless-${version}.tgz";
    hash = "sha512-S1d/hxLKvCUG2g5tRyXFkzPqMs3Ntw1tDyzoF2yfHGRuB4B+Mi3X2vgT8LbfQKrkEEi3LfJRdXtYzAVHcbpccw==";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  nodejs = pkgs.nodejs_22;
  npmDepsHash = "sha256-nqI//dGGWRm4kM0YXkBR5p7TmxllXcBV8oUzU5YqrvE=";
  dontNpmBuild = true;

  # better-sqlite3 compiles its native addon with node-gyp.
  nativeBuildInputs = [ pkgs.python3 ] ++ pkgs.lib.optional pkgs.stdenv.isDarwin pkgs.cctools;

  meta = {
    description = "Headless client for Obsidian Sync";
    homepage = "https://obsidian.md/help/sync/headless";
    license = pkgs.lib.licenses.unfree;
    mainProgram = "ob";
  };
}
