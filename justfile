default:
    sudo nixos-rebuild switch --flake .

darwin *args:
    nix run nix-darwin -- switch --flake ".#work" {{ args }}
