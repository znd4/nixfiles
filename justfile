default:
    sudo nixos-rebuild switch --flake .

alias hm := home-manager

home-manager:
    nix run home-manager -- switch --flake .

nixos:
    sudo nixos-rebuild switch --flake .

darwin *args:
    nix run nix-darwin -- switch --flake ".#work" {{ args }}
