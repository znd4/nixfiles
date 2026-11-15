## znd4\.certificateAuthorities

Extra certificate authorities, as PEM text, to trust on top of the
Mozilla bundle from ` pkgs.cacert `\. When this is not empty, git, Node,
Python requests and OpenSSL use
` znd4.certificateAuthorityBundle `\.



*Type:*
list of string



*Default:*
` [ ] `

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.certificateAuthorityBundle



Path of a CA bundle: ` pkgs.cacert ` followed by
` znd4.certificateAuthorities `\. ` null ` when no extra
authorities are set\. Derived; do not set\.



*Type:*
null or string *(read only)*

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.flakePath



Checkout of this flake that ` nh ` switches from\.



*Type:*
string



*Default:*
` "${config.home.homeDirectory}/nixfiles" `

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.hostname



Name of the machine this configuration is for, as in the
` homeConfigurations."<user>@<hostname>" ` attribute\. It selects the
host’s entry in the flake’s ` keys `\. To change behavior per machine,
add an option that names the capability (see ` znd4.ssh.agent `)
rather than testing this value\.



*Type:*
string



*Example:*
` "desktop" `

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.keys



SSH public keys by host name\. Each key becomes an ` IdentityFile `
match block in the SSH config; ` github.com ` is also the git signing
key\. Each entry of ` defaultKeys ` in flake\.nix is set with
` mkDefault `, and each entry of ` keys.${hostname} ` with priority
900, so a host can add or override single entries\.



*Type:*
attribute set of string

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.knownHosts



` known_hosts ` lines, grouped by host name\. The SSH config uses them
as its ` UserKnownHostsFile `\. Each entry of ` knownHosts ` in flake\.nix
is set with ` mkDefault `\.



*Type:*
attribute set of strings concatenated with “\\n”

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.rclone\.passwordCommand



Command that prints the password that encrypts rclone\.conf\. The
rclone wrapper sets it as the default ` RCLONE_PASSWORD_COMMAND `, so
a single command can still override it\.



*Type:*
string



*Default:*
` "${pkgs._1password-cli}/bin/op read op://Private/rclone/password" `

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.sesh\.githubOrgs



GitHub organizations that the clone-pick repo picker lists repositories from\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "znd4"
]
```

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.sesh\.gitlabHosts



GitLab hosts that the clone-pick repo picker (tmux M-m, herdr alt+m) lists projects from\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "gitlab.example.com"
]
```

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.ssh\.agent



The SSH agent that holds this machine’s keys\.

 - ` 1password `: the 1Password agent\. ssh and the shells use its socket,
   and git signs commits with ` op-ssh-sign `\.
 - ` secretive `: the Secretive agent (macOS only)\. ssh and the shells use
   its socket\.
 - ` system `: the operating system’s agent\. On macOS, each shell finds
   the launchd agent (or starts one at ` ~/.ssh/agent.sock `) and
   loads the keys stored in the keychain into it\. On Linux, the session’s agent
   is used as it is\. ssh uses ` SSH_AUTH_SOCK ` in both cases\.



*Type:*
one of “1password”, “secretive”, “system”

*Declared by:*
 - [home-manager/programs](https://github.com/znd4/nixfiles/blob/main/home-manager/programs)



## znd4\.user\.email



Email address for commits (git ` user.email `, jj ` user.email `)\.



*Type:*
string



*Default:*
` "zane@znd4.dev" `

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.user\.name



Full name for commits (git ` user.name `, jj ` user.name `)\.



*Type:*
string



*Default:*
` "Zane Dufour" `

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)



## znd4\.workDir



Absolute path of the directory that repos are cloned into, as
\<workDir>/\<host>/\<path>\. The repo pickers (tmux M-m, herdr alt+m),
the review popups and new tmux/herdr sessions use it\.



*Type:*
string



*Default:*
` "${config.home.homeDirectory}/Work" `

*Declared by:*
 - [home-manager/modules/znd4\.nix](https://github.com/znd4/nixfiles/blob/main/home-manager/modules/znd4.nix)


