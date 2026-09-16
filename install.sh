#!/bin/bash

brew update
brew install coreutils gh pyenv

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

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash

nvm install --lts
nvm alias default "lts/*"

./update.sh

pyenv install 3.14
pyenv global 3.14
