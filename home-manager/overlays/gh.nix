{ ... }:
(final: prev: {
  gh = final.writeShellApplication {
    name = "gh";
    runtimeInputs = [
      final._1password-cli
      prev.gh
    ];
    text = ''
      #!${final.runtimeShell}
      # 'exec' replaces the shell process with the 'op' process, which is
      # more efficient and handles signals correctly.
      # "$@" forwards all arguments, preserving spaces and special characters.
      exec op plugin run -- gh "$@"
    '';
  };
})
