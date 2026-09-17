" Explicit, because the ALE settings below use line continuations, which
" are ignored in 'compatible' mode.
set nocompatible

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
nmap <leader>lc :lclose<CR>
nmap <leader>lo :lopen<CR>
nmap <leader>ts :tab split<CR>
nmap <leader>tc :tab close<CR>

" --- ALE -------------------------------------------------------------------
" Python is handled by exactly two tools, both installed as isolated uv tools
" by python-tools.sh:
"   ruff   diagnostics and formatting -- replaces flake8, pylint, autopep8,
"          isort, pycodestyle, pyflakes, pydocstyle, pylama and black
"   pylsp  the LSP features: completion, go-to-definition, hover, references
"          and rename
let g:ale_linters_explicit = 1
let g:ale_linters = {'python': ['ruff', 'pylsp']}
let g:ale_fixers = {
\   'python': ['ruff', 'ruff_format'],
\   '*': ['remove_trailing_lines', 'trim_whitespace'],
\ }
let g:ale_fix_on_save = 1

" Prefer the tools on PATH (the uv tool installs) over hunting for a
" virtualenv, but let a uv project supply its own pinned versions.
let g:ale_use_global_executables = 1
let g:ale_python_auto_uv = 1

" ALE is the completion source, so no separate completion plugin is needed.
let g:ale_completion_enabled = 1
let g:ale_completion_autoimport = 1

" ruff owns diagnostics, so switch off the linters pylsp bundles -- otherwise
" the same warning is reported twice. Leave jedi and rope on, since those are
" what provide the LSP features.
let g:ale_python_pylsp_config = {
\   'pylsp': {
\     'plugins': {
\       'pycodestyle': {'enabled': v:false},
\       'pyflakes': {'enabled': v:false},
\       'pylint': {'enabled': v:false},
\       'mccabe': {'enabled': v:false},
\       'flake8': {'enabled': v:false},
\       'autopep8': {'enabled': v:false},
\       'yapf': {'enabled': v:false},
\       'jedi_completion': {'include_params': v:true},
\       'rope_autoimport': {'enabled': v:true},
\     },
\   },
\ }

" LSP navigation. K for hover follows the vim convention; <leader>h is
" already taken by <leader>hs.
nmap <leader>gd :ALEGoToDefinition<CR>
nmap <leader>gt :ALEGoToTypeDefinition<CR>
nmap <leader>gr :ALEFindReferences<CR>
nmap <leader>rn :ALERename<CR>
nmap <leader>ai :ALEImport<CR>
nmap <leader>tb :ALESymbolSearch<Space>
nmap K :ALEHover<CR>
nmap [d :ALEPrevious<CR>
nmap ]d :ALENext<CR>

" use ag for locating files
let g:ctrlp_user_command = 'ag %s -l --nocolor --hidden --ignore .git -g ""'

" use ag for searching
let g:ackprg = 'ag --nogroup --nocolor --column --silent'

" Explicit path: with no argument vim-plug defaults to ~/.vim/plugged under
" vim but ~/.local/share/nvim/plugged under nvim, so the two would not
" share plugins. nvim-init.vim relies on this being one directory.
call plug#begin('~/.vim/plugged')
Plug 'joshdick/onedark.vim'
Plug 'airblade/vim-gitgutter'
Plug 'altercation/vim-colors-solarized'
Plug 'editorconfig/editorconfig-vim'
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
" vim-python-pep8-indent is bundled by vim-polyglot above.
Plug 'dense-analysis/ale'
Plug 'pangloss/vim-javascript'
Plug 'chr4/nginx.vim'
Plug 'mtth/scratch.vim'
call plug#end()

syntax on
colorscheme onedark
