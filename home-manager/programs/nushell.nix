{ config, ... }:
{
  programs.nushell = {
    enable = true;

    # `settings` assigns each key onto `$env.config` one at a time. That matters:
    # the old env.nu did `$env.config = { edit_mode: vi }`, a whole-record
    # assignment that drops every other field on the floor.
    settings = {
      edit_mode = "vi";

      # alt-e opens $EDITOR on the current prompt buffer, like fish's alt-e.
      # reedline already binds ctrl-o to the same event in every mode; this is
      # the extra binding, not a replacement.
      keybindings = [
        {
          name = "open_editor";
          modifier = "alt";
          keycode = "char_e";
          mode = [
            "emacs"
            "vi_normal"
            "vi_insert"
          ];
          event.send = "openeditor";
        }
      ];
    };

    # home.sessionVariables only reaches POSIX shells and fish, so nushell picks
    # EDITOR up by inheritance from a parent shell -- and gets nothing when it is
    # the login shell, which leaves alt-e/ctrl-o with no editor to open. Set it
    # explicitly here. This has to be extraConfig rather than extraEnv: env.nu
    # runs first, so a value set there loses to the `load-env` block that
    # home-manager writes at the top of config.nu.
    extraConfig = ''
      # Use nvr inside neovim terminals, so :terminal edits reuse the outer nvim.
      $env.EDITOR = if ($env.NVIM? | is-not-empty) {
        "nvr -cc split --remote-wait"
      } else {
        "${config.home.sessionVariables.EDITOR}"
      }
    '';
  };
}
