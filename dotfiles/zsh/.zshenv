#!/usr/bin/env zsh
# removed for now b.c. this was breaking `sk` (skim)
# export TERMINFO_DIRS=`find /usr/share/terminfo -type d | tr '\n' ':'`
export LANG=en_US.UTF-8

unset CURL_CA_BUNDLE

# fzf
export FZF_COMPLETION_DIR_COMMANDS="cd z pushd rmdir"


# use neovim as manpager
add_to_path() {
    directory=$1
	# todo: if not -d $directory; then mkdir --parents $directory
	# fi
	# export PATH=$...
    export PATH="$directory:$PATH"
}

add_to_path "$HOME/bin"

# set PATH so it includes user's private bin if it exists
add_to_path "$HOME/.local/bin"

export LESS="-FX"
if command -v most >/dev/null; then
    export PAGER=most
fi

#AWSume alias to source the AWSume script
alias awsume="source \$(pyenv which awsume)"

#Auto-Complete function for AWSume
#Auto-Complete function for AWSume
fpath=(~/.awsume/zsh-autocomplete/ $fpath)
