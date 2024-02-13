default:
    sudo nixos-rebuild switch --flake .

darwin:
    nix run nix-darwin -- switch --show-trace --flake ".#work"
