# SSH client config and the SSH agent. One option, znd4.ssh.agent, chooses
# the agent for all the places that need to agree on it: ssh's
# IdentityAgent, SSH_AUTH_SOCK in the interactive shells (fish, bash, zsh,
# nushell), and git's SSH signing program.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv) isDarwin;
  cfg = config.znd4.ssh;
  home = config.home.homeDirectory;

  # Agent socket for each agent that has a fixed socket. "system" has
  # none: on macOS the launchd agent's socket changes after a reboot, so each
  # shell asks macosSystemAgent for it at startup and ssh reads
  # SSH_AUTH_SOCK.
  sockets = {
    "1password" =
      if isDarwin then
        "${home}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
      else
        "${home}/.1password/agent.sock";
    secretive = "${home}/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
  };
  socket = sockets.${cfg.agent} or null;

  # Prints the socket of a working system agent on macOS, or nothing.
  # 1. Try the launchd-managed agent (socket path changes after reboots).
  # 2. Fall back to a persistent agent at ~/.ssh/agent.sock.
  # Then loads keychain-stored keys into the agent if none are loaded:
  # macOS no longer does this automatically at login. It calls Apple's
  # ssh-add by path: nixpkgs' openssh has no --apple-load-keychain.
  macosSystemAgent = pkgs.writeShellScript "ssh-system-agent" ''
    sock=$(/bin/launchctl print "gui/$(/usr/bin/id -u)/com.openssh.ssh-agent" 2>/dev/null |
      /usr/bin/sed -n 's/.*SSH_AUTH_SOCK => //p' | /usr/bin/tail -n 1)
    if [ -z "$sock" ] || [ ! -S "$sock" ]; then
      # launchd socket is dead (e.g. /private/tmp was cleaned).
      # Start or reuse a persistent agent.
      sock=$HOME/.ssh/agent.sock
      [ -S "$sock" ] || /usr/bin/ssh-agent -a "$sock" >/dev/null 2>&1
      [ -S "$sock" ] || exit 0
    fi
    if ! SSH_AUTH_SOCK=$sock /usr/bin/ssh-add -l >/dev/null 2>&1; then
      SSH_AUTH_SOCK=$sock /usr/bin/ssh-add --apple-load-keychain >/dev/null 2>&1
    fi
    printf '%s\n' "$sock"
  '';
  # The socket is only known at run time: ask macosSystemAgent.
  dynamic = socket == null && isDarwin;

  posixInit =
    if socket != null then
      ''
        export SSH_AUTH_SOCK=${lib.escapeShellArg socket}
      ''
    else if dynamic then
      ''
        _ssh_sock="$(${macosSystemAgent})"
        if [ -n "$_ssh_sock" ]; then
          export SSH_AUTH_SOCK="$_ssh_sock"
        fi
        unset _ssh_sock
      ''
    else
      "";

  opSshSign =
    if isDarwin then
      "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    else
      "/opt/1Password/op-ssh-sign";
in
{
  options.znd4.ssh.agent = lib.mkOption {
    type = lib.types.enum [
      "1password"
      "secretive"
      "system"
    ];
    description = ''
      The SSH agent that holds this machine's keys.

      - `1password`: the 1Password agent. ssh and the shells use its socket,
        and git signs commits with `op-ssh-sign`.
      - `secretive`: the Secretive agent (macOS only). ssh and the shells use
        its socket.
      - `system`: the operating system's agent. On macOS, each shell finds
        the launchd agent (or starts one at {file}`~/.ssh/agent.sock`) and
        loads the keys stored in the keychain into it. On Linux, the session's agent
        is used as it is. ssh uses `SSH_AUTH_SOCK` in both cases.
    '';
  };

  config = {
    assertions = [
      {
        assertion = cfg.agent == "secretive" -> isDarwin;
        message = "znd4.ssh.agent = \"secretive\" needs macOS.";
      }
    ];

    programs.ssh = {
      enable = true;
      # Goes in the `Host *` block. The socket paths can contain spaces.
      extraConfig = lib.mkIf (socket != null) ''IdentityAgent "${socket}"'';

      # home-manager's implicit `Host *` defaults only restated OpenSSH's own.
      enableDefaultConfig = false;
      matchBlocks = {
        "*" = {
          # "yes" (not "confirm"): with "confirm", every key *use* needs an
          # interactive TouchID/prompt, which silently fails non-interactive git
          # pushes (the key is in the agent but each use is blocked). No-op on
          # machines whose IdentityAgent is Secretive/1Password (those manage
          # keys internally and ignore this).
          addKeysToAgent = "yes";
          userKnownHostsFile = "${
            (pkgs.writeText "known_hosts" (
              builtins.concatStringsSep "\n" (
                lib.attrsets.mapAttrsToList (name: value: value) config.znd4.knownHosts
              )
            ))
          }";
        };
      }
      // lib.attrsets.mapAttrs (name: value: {
        identitiesOnly = true;
        identityFile = "${pkgs.writeText "${name}_id_rsa.pub" value}";
      }) config.znd4.keys
      // {
        # The desktop gaming PC, reached as nobara-pc.local while it runs
        # Nobara (it is meant to go back to NixOS). Same 1Password "Desktop"
        # key as desktop.local.
        desktop = {
          hostname = "nobara-pc.local";
          user = "znd4";
          extraOptions.HostKeyAlias = "desktop";
          identitiesOnly = true;
          identityFile = "${pkgs.writeText "desktop_id_rsa.pub" config.znd4.keys."desktop.local"}";
        };
      };
    };

    # SSH_AUTH_SOCK for each interactive shell, at the end of its init.
    # Nothing before it reads SSH_AUTH_SOCK.
    programs.fish.interactiveShellInit = lib.mkAfter (
      if socket != null then
        ''
          set -gx SSH_AUTH_SOCK "${socket}"
        ''
      else if dynamic then
        ''
          set -l _ssh_sock (${macosSystemAgent})
          if test -n "$_ssh_sock"
            set -gx SSH_AUTH_SOCK $_ssh_sock
          end
        ''
      else
        ""
    );
    programs.bash.initExtra = lib.mkAfter posixInit;
    programs.zsh.initContent = lib.mkAfter posixInit;
    programs.nushell.extraConfig = lib.mkAfter (
      if socket != null then
        ''
          $env.SSH_AUTH_SOCK = "${socket}"
        ''
      else if dynamic then
        ''
          let _ssh_sock = (^${macosSystemAgent} | str trim)
          if ($_ssh_sock | is-not-empty) { $env.SSH_AUTH_SOCK = $_ssh_sock }
        ''
      else
        ""
    );

    programs.git.settings.gpg.ssh.program = lib.mkIf (cfg.agent == "1password") opSshSign;
  };
}
