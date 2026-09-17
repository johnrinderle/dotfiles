" Neovim entry point. Deliberately thin: it reuses ~/.vimrc so there is one
" configuration to maintain and vim and nvim behave identically.
"
" Symlinked to ~/.config/nvim/init.vim by install.sh.

set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath

" Point the Python provider at the scratch venv, which is where requirements.txt
" (and therefore pynvim) is installed. Naming it explicitly means the provider
" keeps working when the default Python moves to a new version -- previously it
" tracked `pyenv global` and broke silently on every upgrade.
let s:dev_python = expand('~/.venvs/dev/bin/python')
if executable(s:dev_python)
    let g:python3_host_prog = s:dev_python
endif

source ~/.vimrc
