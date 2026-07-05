---
name: eu5-files
description: Inspect Europa Universalis V (EU5 / EUV) data on this machine — user directory, logs, and .eu5 save archives — and know when to fall back to the EU5 wiki. Use when the user asks about their EU5 game, saves, playthroughs, or game data "installed locally".
---

# eu5-files

How to peruse Europa Universalis V files on this machine, and what is (and is
not) available locally.

## What lives where

The **user directory** is iCloud-synced Documents:

```
~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Paradox Interactive/Europa Universalis V/
```

Notable contents:

- `save games/*.eu5` — save files (see format below)
- `continue_game.json` — most recent save name, real-world date, game version
- `logs/` — `game.log`, `error.log`, `setup.log` (exe version/build), `system.log` (hardware/OS)
- `playsets.json`, `pdx_settings.json` — mods and settings

**The game install itself is NOT on this Mac.** `logs/system.log` reports a
`VirtualApple` CPU on Windows 10 — the game runs under a Windows
VM/compatibility layer, and only the Documents folder syncs here via iCloud.
Do not go hunting for `game/` data files, Steam installs, or CrossOver/Whisky
bottles; they don't exist locally. (Re-check `system.log` if this seems to
have changed.)

## Save file format (`.eu5`)

A `.eu5` file is a **zip archive** with extra leading bytes — `unzip` prints a
warning ("extra bytes at beginning") and exits non-zero but **extracts
correctly**; check that the files landed rather than trusting the exit code.
Copy the save to a scratch directory first (don't unzip inside the iCloud
folder). It contains two members:

- `gamestate` (~100 MB) — mixed text and binary. Coat-of-arms and some blocks
  are plain text, but most identifiers (country tags, ranks, etc.) are stored
  as **binary indices into the string table**, so `grep MLO gamestate` finding
  nothing does NOT mean Milan is absent from the save.
- `string_lookup` (~1 MB) — the string table. This is the useful one for
  discovery: `strings string_lookup | grep -i <term>` reveals identifiers,
  e.g. `mlo_*` prefixes (Milan's tag is `MLO`), `rank_county`, dynasty and
  culture names.

Extracting *structured* facts (e.g. "what rank is X in this save") from the
binary gamestate is not practical with shell tools — the string table only
tells you which identifiers exist, not how they relate.

## Useful reference points learned so far

- Country rank tiers: `rank_county`, `rank_duchy`, `rank_kingdom`,
  `rank_empire` (plus `rank_japanese_*` variants).
- Milan (tag `MLO`) starts as a **county** in 1337 — a Visconti-dominated
  republic that can still form royal marriages.

## When local files can't answer

For game-data questions (starting setups, mechanics, what a country's rank
is), the local user directory usually can't answer definitively — use the
wiki:

- Landing page for file/database structure: https://eu5.paradoxwikis.com/Modding
- Country pages: `https://eu5.paradoxwikis.com/<Country>` (e.g. /Milan)
