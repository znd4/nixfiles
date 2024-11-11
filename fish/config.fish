if status is-interactive
    # Commands to run in interactive sessions can go here
    fish_vi_key_bindings
    atuin init fish | source
end
fish_add_path /opt/homebrew/bin
fish_add_path ~/.cargo/bin


direnv hook fish | source

source "$(brew --prefix)/share/google-cloud-sdk/path.fish.inc"


# kubectl-kots completion fish | source

starship init fish | source
zoxide init fish | source

# source ~/.config/op/plugins.sh

alias vi=nvim
alias bh="bat -l help"
alias ipy="py -m IPython"

abbr k kubectl
abbr g git
# abbr gt git town
abbr ky kubectl get -o yaml
abbr kk k9s
abbr kr kubectl --context rancher-desktop
abbr pc pre-commit
abbr -a by --position anywhere --set-cursor "% | bat -l yaml"
abbr -a bh --position anywhere --set-cursor "% | bat -l help"

##### carapace.sh completions
set -gx CARAPACE_EXCLUDES kubectl
set -Ux CARAPACE_BRIDGES 'zsh,fish,bash,inshellisense' # optional
mkdir -p ~/.config/fish/completions
carapace --list | awk '{print $1}' | xargs -P0 -I{} touch ~/.config/fish/completions/{}.fish # disable auto-loaded completions (#185)
carapace _carapace | source


### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
set --export --prepend PATH "/Users/znd4/.rd/bin"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)
