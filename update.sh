#!/bin/sh
brew update && brew upgrade && brew cleanup -s
pip install -U -r ~/.vim/requirements.txt
pushd ~/.vim
git submodule update --remote --recursive
popd
