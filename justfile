default:
    sudo nixos-rebuild switch --flake .

alias hm := home-manager

home-manager ARGS='.':
    nix run .#home-manager-switch {{ ARGS }}

nixos:
    sudo nixos-rebuild switch --flake .

darwin *args:
    nix run nix-darwin -- switch --flake ".#work" {{ args }}
