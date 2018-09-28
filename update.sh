#!/bin/sh
brew update && brew upgrade && brew cleanup -s
pip install -U -r ~/.vim/requirements.txt
npm install -g cloc legally license-checker
npm update -g
pushd ~/.vim
git submodule update --remote --recursive
popd
