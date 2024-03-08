# Zane's Nix files

## Setup

```shell
git clone https://github.com/znd4/nixfiles
cd ./nixfiles
# Only needed during system setup
export NIX_CONFIG="experimental-features = nix-command flakes"
```

### nix-darwin

```shell
darwin-rebuild switch --flake ".<hostname>"
```

### NixOS

```sh
sudo nixos-rebuild switch --flake ".#<hostname>"
```

### Home Manager

```sh
home-manager switch --flake .
```

## Future plans

- [] Config for VMs
