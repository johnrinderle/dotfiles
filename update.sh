#!/bin/bash
set -e -x

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
brew bundle --file ~/Brewfile
brew upgrade
brew cleanup -s

pip3 install -U pip setuptools wheel
pip3 install -U -r ~/requirements.txt

npm i -g --force npm
npm update -g

vim +'PlugInstall --sync' +qa
