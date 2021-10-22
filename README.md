# Zane's Dotfile

This is all fully ripped off from [this awesome article](https://www.atlassian.com/git/tutorials/dotfiles)

## Setup process on new machine

Create config alias

```sh
alias config='/usr/bin/env git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
```

Clone

```sh
git clone --bare https://github.com/zdog234/dotfiles $HOME/.cfg
```

## Install pre-commit hooks

Install go and shfmt

```sh
brew install go
go install mvdan.cc/sh/v3/cmd/shfmt@v3.2.2
```

```sh
GIT_DIR=.cfg GIT_WORK_TREE=$HOME pre-commit install
```
