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

run pre-commit install

```sh
GIT_DIR=.cfg GIT_WORK_TREE=$HOME pre-commit install
```
