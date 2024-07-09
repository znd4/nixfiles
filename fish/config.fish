if status is-interactive
    # Commands to run in interactive sessions can go here
    fish_vi_key_bindings
end
fish_add_path /opt/homebrew/bin


direnv hook fish | source

source "$(brew --prefix)/share/google-cloud-sdk/path.fish.inc"


# kubectl-kots completion fish | source

starship init fish | source
zoxide init fish | source

alias g=git
alias vi=nvim
alias bh="bat -l help"
alias by="bat -l yaml"
alias kkots="kubectl-kots"

abbr k kubectl
source ~/.config/op/plugins.sh
