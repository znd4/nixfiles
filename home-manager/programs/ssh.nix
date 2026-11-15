# SSH client config and the SSH agent. One option, znd4.ssh.agent, chooses
# the agent for all three places that need to agree on it: ssh's
# IdentityAgent, SSH_AUTH_SOCK in fish, and git's SSH signing program.
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
  # none: on macOS the launchd agent's socket changes after a reboot, so fish
  # finds it at startup and ssh reads SSH_AUTH_SOCK.
  sockets = {
    "1password" =
      if isDarwin then
        "${home}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
      else
        "${home}/.1password/agent.sock";
    secretive = "${home}/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
  };
  socket = sockets.${cfg.agent} or null;

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

      - `1password`: the 1Password agent. ssh and fish use its socket, and
        git signs commits with `op-ssh-sign`.
      - `secretive`: the Secretive agent (macOS only). ssh and fish use its
        socket.
      - `system`: the operating system's agent. On macOS, fish finds the launchd
        agent (or starts one at {file}`~/.ssh/agent.sock`) and loads the
        keys stored in the keychain into it. On Linux, the session's agent
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
        # Nobara gaming PC; same 1Password "Desktop" key as desktop.local.
        desktop = {
          hostname = "nobara-pc.local";
          user = "znd4";
          extraOptions.HostKeyAlias = "desktop";
          identitiesOnly = true;
          identityFile = "${pkgs.writeText "desktop_id_rsa.pub" config.znd4.keys."desktop.local"}";
        };
      };
    };

    # At the end of the interactive init. Nothing before it reads
    # SSH_AUTH_SOCK.
    programs.fish.interactiveShellInit = lib.mkAfter (
      if socket != null then
        ''
          set -gx SSH_AUTH_SOCK "${socket}"
        ''
      else if isDarwin then
        ''
          # Ensure a working SSH agent on macOS.
          # 1. Try the launchd-managed agent (socket path changes after reboots)
          # 2. Fall back to a persistent agent at ~/.ssh/agent.sock
          set -l _ssh_sock (launchctl print gui/(id -u)/com.openssh.ssh-agent 2>/dev/null | string match -r 'SSH_AUTH_SOCK => (.+)' | tail -1)
          if test -n "$_ssh_sock" -a -S "$_ssh_sock"
            set -gx SSH_AUTH_SOCK $_ssh_sock
          else
            # launchd socket is dead (e.g. /private/tmp was cleaned).
            # Start or reuse a persistent agent.
            set -l _fallback ~/.ssh/agent.sock
            if not test -S "$_fallback"
              /usr/bin/ssh-agent -a "$_fallback" >/dev/null 2>&1
            end
            if test -S "$_fallback"
              set -gx SSH_AUTH_SOCK $_fallback
            end
          end
          # Load keychain-stored keys into the agent if none are loaded.
          # macOS no longer does this automatically at login.
          if not ssh-add -l >/dev/null 2>&1
            ssh-add --apple-load-keychain 2>/dev/null
          end
        ''
      else
        ""
    );

    programs.git.settings.gpg.ssh.program = lib.mkIf (cfg.agent == "1password") opSshSign;
  };
}
