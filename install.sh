#!/bin/bash

brew install gh coreutils

DOTFILES_PATH=`realpath $0 | xargs dirname`
pushd ~
ln -s $(grealpath --relative-to="." $DOTFILES_PATH/.vimrc) .vimrc
ln -s $(grealpath --relative-to="." $DOTFILES_PATH/.zprofile) .zprofile
ln -s $(grealpath --relative-to="." $DOTFILES_PATH/Brewfile) Brewfile
ln -s $(grealpath --relative-to="." $DOTFILES_PATH/requirements.txt) requirements.txt
ln -s $(grealpath --relative-to="." $DOTFILES_PATH/update.sh) update.sh
popd

curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash

nvm install 16
nvm install --lts
nvm use --lts

pyenv install 3.9
pyenv install 3.11
pyenv global 3.11

./update.sh
