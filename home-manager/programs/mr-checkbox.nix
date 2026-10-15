{ pkgs, ... }:
let
  # Tick or clear one checkbox line in a GitLab MR description:
  #   mr-checkbox <project-path> <iid> --match "<text>" --check|--uncheck
  # ../bin/mr-checkbox.py is a PEP 723 script (https://peps.python.org/pep-0723/)
  # with no dependencies. It runs through `uv run --script`, as action-dag does.
  #
  # glab comes from the user's PATH, not from this file, so that the script
  # uses the user's own glab login.
  #
  # Tests: uv run --script home-manager/bin/tests/test_mr_checkbox.py
  mrCheckbox = pkgs.writeShellApplication {
    name = "mr-checkbox";
    runtimeInputs = with pkgs; [
      uv
      coreutils
    ];
    text = ''
      exec uv run --script ${../bin/mr-checkbox.py} "$@"
    '';
  };
in
{
  home.packages = [ mrCheckbox ];
}
