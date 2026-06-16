#!/bin/bash
set -e -x

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
brew bundle install --file ~/Brewfile
brew upgrade -y
brew cleanup -s

pip3 install -U pip setuptools wheel
pip3 install -U -r ~/requirements.txt

npm i -g --force npm
npm update -g

vim +'PlugInstall --sync' +qa
