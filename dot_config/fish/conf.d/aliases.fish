alias ddgr="BROWSER=firefox command ddgr"
alias g=git

alias dotfiles="GIT_WORK_TREE=~ GIT_DIR=~/.cfg"

alias bat=batcat

alias ls='ls --color=auto'
alias grep='grep --color=auto'

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

alias tn="terminal-notifier"
alias dc="docker-compose"
alias ga="git add"
alias gc="git commit"
alias gd="git diff"
alias gp="git push"
alias gs="git status"
alias gcl=gcloud
alias ktl="kubectl"
alias kget="ktl get"
alias kdel="ktl delete"
alias klogs="ktl logs"
alias remimp="autoflake \
        --in-place \
        --remove-unused-variables \
        --recursive \
        --remove-all-unused-imports \
        --ignore-init-module-imports \
        ."

# copy to clipboard
alias xclip="xclip -selection c"

# gcloud
alias gssh='gcloud alpha cloud-shell ssh --authorize-session'
alias gsshmount='gcloud alpha cloud-shell get-mount-command'

# prettier
alias prettier="npx prettier"
alias pr=prettier



# ipython
alias ipy="python3 -m IPython"
alias ipy3="python3 -m IPython"
alias ipy36="python3.6 -m IPython"
alias ipy37="python3.7 -m IPython"
alias ipy38="python3.8 -m IPython"
alias ipy39="python3.9 -m IPython"
alias ipy310="python3.10 -m IPython"

# Signal Desktop App
if test (uname -s) = "Darwin";
    alias signal="/Applications/Signal.app/Contents/MacOS/Signal"
end

# py3x
if which py > /dev/null;
    alias py3="py -3"
    alias py36="py -3.6"
    alias py37="py -3.7"
    alias py38="py -3.8"
    alias py39="py -3.9"
    alias py310="py -3.10"
else;
    echo "python-launcher not installed. brew install python-launcher"
end
