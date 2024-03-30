default:
    sudo nixos-rebuild switch --flake .

home-manager:
    home-manager switch --flake .

nixos:
    sudo nixos-rebuild switch --flake .

darwin *args:
    nix run nix-darwin -- switch --flake ".#work" {{ args }}
