execute pathogen#infect()

set background=dark
colorscheme solarized

set nu
set list
set showmatch
set hlsearch
set ignorecase
set smartcase

set autoindent
set tabstop=4
set softtabstop=4
set shiftwidth=4
set expandtab

autocmd Filetype css setlocal ts=2 sts=2 sw=2 expandtab
autocmd Filetype html setlocal ts=2 sts=2 sw=2 expandtab
autocmd Filetype java setlocal ts=4 sts=4 sw=4 noexpandtab
autocmd Filetype javascript setlocal ts=2 sts=2 sw=2 expandtab
autocmd Filetype xml setlocal ts=2 sts=2 sw=2 expandtab

nmap <F8> :TagbarToggle<CR>

nmap <leader>hs :set hlsearch! hlsearch?

let NERDTreeShowHidden=1

let g:syntastic_python_flake8_args='--ignore=E501'

set wildignore+='*.pyc'
let g:ctrlp_custom_ignore = '\.pyc$'
