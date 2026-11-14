# Vaults that the 1Password SSH agent offers keys from.
# Without this file the agent offers only the personal vault. With it, the
# agent offers only the vaults listed here, so keep "Private".
# https://developer.1password.com/docs/ssh/agent/config/
{
  lib,
  _1password_ssh ? false,
  ...
}:
{
  config = lib.mkIf _1password_ssh {
    xdg.configFile."1Password/ssh/agent.toml".text = ''
      [[ssh-keys]]
      vault = "Private"

      # homelab admin key (github.com/znd4/homelab, docs/bootstrap.md)
      [[ssh-keys]]
      vault = "Homelab"
    '';
  };
}
