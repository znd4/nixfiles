---
name: nixfiles
description: How to contribute to znd4's nixfiles repo (~/nixfiles) — flake layout, homeConfigurationFactory specialArgs, adding machines/modules/Claude skills, build+switch commands, and the non-NixOS (Nobara) caveats. Use when adding or changing anything in the nix config — packages, programs, dotfiles, hosts, or agent skills.
---

# nixfiles

Working conventions for `~/nixfiles`, a flake managing NixOS, nix-darwin, and
standalone home-manager across machines. CLAUDE.md in the repo covers the
basics; this skill records the non-obvious mechanics.

## Hosts

| host | platform | managed by |
|---|---|---|
| `desktop` | **Nobara** (Fedora-based, rebuilt mid-2026; formerly NixOS) | home-manager ONLY |
| `t470` | NixOS | nixos + home-manager |
| `mac-mini`, `Zanes-MacBook-Neo.local` | macOS | nix-darwin + home-manager |

(`work` was a macOS host, decommissioned July 2026 — its flake entries are
being removed; don't add new config for it.)

User is `znd4` everywhere. `homeConfigurations` are keyed `"user@hostname"` —
if a machine's hostname doesn't match its entry in flake.nix, `just
home-manager` won't find the config.

**Nobara caveat:** on `desktop`, home-manager cannot manage system state — no
sshd/avahi/firewall config, no systemd system units, no `/etc`. User-level
files and `systemd.user.services` only. Fedora SELinux may also block daemons
(e.g. sshd) from reading files symlinked into `/nix/store`; if enforcing, copy
via `home.activation` instead of `home.file`.

## Where things go

- `flake.nix` — all outputs. `homeConfigurationFactory` (~line 240) builds each
  home config; per-machine entries are the list at the bottom (~line 292).
  Flake-level attrsets: `knownHosts` (SSH host keys, baked read-only into
  `~/.ssh` known_hosts), `defaultKeys` / `keys` (authorized public keys).
- `home-manager/programs/*.nix` — **auto-imported**: every file in the
  directory is a module on all machines. Drop a file in, it's live; guard
  platform-specific bits with `pkgs.stdenv.isLinux`/`isDarwin`.
- `home-manager/nixos/` and `home-manager/darwin/` — platform-only home modules.
- `xdg-config/` — raw dotfiles (nvim, fish, etc.), linked via xdg.configFile.
- `pkgs/` — custom Go packages.
- `nixos/machines/*.nix`, `darwin/` — system-level per-machine config.

## specialArgs available in every home module

`outputs`, `knownHosts`, `keys` (= `defaultKeys // keys.${hostname}` — e.g.
`keys."desktop.local"` is the desktop's authorized pubkey), `hostname`,
`username`, `system`, `stateVersion`, `identityAgent`, `_1password_ssh`,
`seshClConfig`, `certificateAuthority`.

## Adding a Claude agent skill

1. `home-manager/claude-skills/<name>/SKILL.md` (frontmatter: `name`,
   `description` with explicit "Use when …" triggers).
2. `home-manager/programs/<name>.nix` installing it to `~/.claude/skills/`:
   simple case is `home.file.".claude/skills/<name>" = { source =
   ../claude-skills/<name>; recursive = true; }` (see `eu5.nix`); if the skill
   ships scripts, mirror the `mkSkillFiles` helper in `hunk-mr.nix`.
3. No import wiring needed — `programs/` auto-imports.

## Build / verify / switch

```shell
just home-manager      # switch home config for current user@hostname
just darwin            # nix-darwin switch (macOS)
just nixos             # nixos-rebuild switch (NixOS)
# eval-check a specific host without switching:
nix build .#homeConfigurations."znd4@desktop".activationPackage --dry-run
```

Commit style: lowercase imperative summary, optionally followed by a short
"what/why" (`add hunk-mr: review GitLab MRs / GitHub PRs in Hunk`).

## SSH / keys plumbing

`~/.ssh/config` and known_hosts are generated read-only into the nix store.
Host key changes (machine reinstalls!) require updating `knownHosts` in
flake.nix and re-switching — you cannot `ssh-keyscan >> known_hosts`. The
1Password agent holds all private keys; per-host `IdentityFile` entries pin a
public key with `IdentitiesOnly yes` so servers don't see six keys and slam
the door with "Too many authentication failures".
