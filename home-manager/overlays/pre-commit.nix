{ certificateAuthority, ... }:
#./pre-commit-cert-overlay.nix
final: prev: {
  # 1. Define our custom certifi package.
  #    We give it a unique name to avoid conflicts.
  custom-certifi = prev.python3Packages.certifi.overrideAttrs (oldAttrs: {
    # Use a postInstall hook to run a command after the original package installs.
    postInstall = ''
      # Append our enterprise certificate to the cacert.pem file.
      # The path to the certifi bundle within the package is dynamic based on the Python version,
      # so we use `prev.python3.libPrefix` to get the correct path (e.g., "python3.12").
      cat ${certificateAuthority} >> $out/lib/${prev.python3.libPrefix}/site-packages/certifi/cacert.pem
    '';
  });

  # 2. Override the pre-commit package.
  pre-commit = prev.pre-commit.overrideAttrs (oldAttrs: {
    # propagatedBuildInputs contains the list of Python dependencies for pre-commit.
    # We need to find the original `certifi` in this list and replace it with our `custom-certifi`.
    propagatedBuildInputs = builtins.map (
      dep: if dep.pname == "certifi" then final.custom-certifi else dep
    ) oldAttrs.propagatedBuildInputs;
  });
}
