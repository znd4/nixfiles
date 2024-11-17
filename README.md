# Zane's Nix files

## Setup

```shell
git clone https://github.com/znd4/nixfiles
cd ./nixfiles
# Only needed during system setup
# (thanks for keeping these ridiculously popular features "experimental", nix)
export NIX_CONFIG="experimental-features = nix-command flakes"
```

### nix-darwin

```shell
hostname=t470
nix run nix-darwin -- switch --flake ".#$hostname"
```

### NixOS

```sh
hostname=t470
sudo nixos-rebuild switch --flake ".#$hostname"
```

### Home Manager

```sh
user=znd4
hostname=work
nix run ".#home-manager-switch" ".#$user@$hostname"
```

## Future plans

- [] Config for VMs
