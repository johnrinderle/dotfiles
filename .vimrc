set nu
set list
set showmatch
set hlsearch
set ignorecase
set smartcase

filetype plugin indent on
set autoindent
set tabstop=4
set softtabstop=4
set shiftwidth=4
set expandtab

autocmd Filetype css setlocal ts=2 sts=2 sw=2 expandtab
autocmd Filetype html setlocal ts=2 sts=2 sw=2 expandtab
autocmd Filetype htmldjango setlocal ts=2 sts=2 sw=2 expandtab
autocmd Filetype javascript setlocal ts=2 sts=2 sw=2 expandtab
autocmd Filetype xml setlocal ts=2 sts=2 sw=2 expandtab
autocmd Filetype java setlocal ts=4 sts=4 sw=4 noexpandtab

set clipboard=unnamed
set mouse=

let mapleader=","
nmap <leader>hs :set hlsearch! hlsearch?<CR>
nmap <leader>rt :retab<CR> :%s/\s\+$//e<CR>
nmap <leader>rf :retab<CR> :%s/\s\+$//e<CR> mzgg=G`z<CR>
nmap <leader>\ :Ack!<Space>
nmap <leader>tb :TagbarToggle<CR>
nmap <leader>lc :lclose<CR>
nmap <leader>lo :lopen<CR>
nmap <leader>ts :tab split<CR>
nmap <leader>tc :tab close<CR>

" ale
let g:ale_python_flake8_options='--ignore=E501,E231'
let g:ale_python_pylint_options='--disable=C0301 --extension-pkg-whitelist=pydantic'

" use ag for locating files
let g:ctrlp_user_command = 'ag %s -l --nocolor --hidden --ignore .git -g ""'

" use ag for searching
let g:ackprg = 'ag --nogroup --nocolor --column --silent'

call plug#begin()
Plug 'joshdick/onedark.vim'
Plug 'airblade/vim-gitgutter'
Plug 'altercation/vim-colors-solarized'
Plug 'editorconfig/editorconfig-vim'
Plug 'joshdick/onedark.vim'
Plug 'kien/ctrlp.vim'
Plug 'mileszs/ack.vim'
Plug 'qpkorr/vim-bufkill'
Plug 'Raimondi/delimitMate'
"Plug 'regedarek/zoomwin'
Plug 'sheerun/vim-polyglot'
Plug 'tomasr/molokai'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-rhubarb'
Plug 'tpope/vim-sensible'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'Vimjas/vim-python-pep8-indent'
Plug 'w0rp/ale'
Plug 'pangloss/vim-javascript'
Plug 'chr4/nginx.vim'
Plug 'mtth/scratch.vim'
call plug#end()

syntax on
colorscheme onedark
