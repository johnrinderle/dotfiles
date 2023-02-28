eval "$(/opt/homebrew/bin/brew shellenv)"

# Prefer homebrew packages
export PATH="$(brew --prefix)/bin:$PATH"

# Python
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Node
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# VRSE
source "/Users/john/src/github.com/vitalsource/vrse/SOURCEME" # Added by VRSE

# Interactive operation
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

# Human readable output
alias df='df -h'
alias du='du -h'

# Show matches in color
alias grep='grep --color'

# Defaults for directory listings
export CLICOLOR=1
alias ls='ls -ahF'
alias dir='ls -l'
alias ll='dir'

# Default editor is vim
export EDITOR=$(which vim)

# Aliases for working with git
# git-status: current status of the working copy
alias gs='git status'
# git-name-status: diff, name and status only, ignore whitespace
alias gns='git diff -w --name-status'
# git-merge: merge, force a merge commit, no auto-commit
alias gm='git merge --no-ff --no-commit'
# git-merge-abort: abort an uncommitted merge
alias gma='git merge --abort'
# git-diff: diff cached changes, ignore whitespace
alias gd='git diff -w'
# git-diff-cached: diff cached changes, ignore whitespace
alias gdc='git diff --cached -w'
# git-commit-push: commit and push cached changes
alias gcp='git commit && git push'
# git-commit-quick: commit with no message and push
alias gcq='git commit --no-edit && git push'
# git-rev-version: short commit hash for HEAD revision
alias grv='git rev-parse --short HEAD'
# git-pull-all: pull for all subdirectories containing a git repo
alias gpa='find . -type d -maxdepth 1 -mindepth 1 | while read i ; do pushd "$i" ; if [[ -e .git ]] ; then git pull ; fi ; popd ; done'

# Quick way out of bracketed paste mode
alias nbp="printf '\e[?2004l'"

# Other configuration
export CLOUDSDK_PYTHON_SITEPACKAGES=1
export PRE_COMMIT_ALLOW_NO_CONFIG=1
