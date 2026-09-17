# Interactive zsh configuration.
#
# Division of labour: .zprofile holds PATH and exported environment, read once
# per login shell. This file holds what only matters at a prompt --
# completions, aliases, keybindings -- and is read by *every* interactive
# shell, including non-login ones like `exec zsh` or a shell inside tmux.
# Aliases used to live in .zprofile, where those shells never saw them.

# --------------------------------------------------------- completions ----

# Homebrew's own completions (brew, git, gh, kubectl, aws, eza, fd, ghostty,
# doggo, ghorg, ...) live in $HOMEBREW_PREFIX/share/zsh/site-functions, which
# `brew shellenv` in .zprofile already added to $fpath.

# Docker Desktop.
[ -d "$HOME/.docker/completions" ] && fpath=("$HOME/.docker/completions" $fpath)

# Google Cloud SDK ships its own PATH and completion snippets.
if [ -n "${HOMEBREW_PREFIX:-}" ]; then
    _gcloud="$HOMEBREW_PREFIX/share/google-cloud-sdk"
    [ -f "$_gcloud/path.zsh.inc" ]       && . "$_gcloud/path.zsh.inc"
    [ -f "$_gcloud/completion.zsh.inc" ] && . "$_gcloud/completion.zsh.inc"
    unset _gcloud
fi

# -C skips re-verifying the completion dump on every start, which is the bulk
# of zsh startup cost. If a newly installed tool has no completion, delete
# ~/.zcompdump and start a new shell.
autoload -Uz compinit
compinit -C -d "$HOME/.zcompdump"

# Lets zsh use bash-style `complete` definitions. Loaded explicitly because
# nvm's completion script needs it -- it previously arrived by accident, as a
# side effect of the gcloud completion script above.
autoload -Uz bashcompinit && bashcompinit

# nvm's completion is bash-style, hence bashcompinit. nvm itself is loaded in
# .zprofile.
[ -s "${NVM_DIR:-$HOME/.nvm}/bash_completion" ] && . "${NVM_DIR:-$HOME/.nvm}/bash_completion"

# uv generates its completions rather than shipping a file.
command -v uv >/dev/null && eval "$(uv generate-shell-completion zsh)"

# ------------------------------------------------------------- aliases ----

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
alias ls='ls -ahF'
alias dir='ls -l'
alias ll='dir'

# Quick way out of bracketed paste mode
alias nbp="printf '\e[?2004l'"

# The scratch Python environment built from requirements.txt
alias dev='source "$DEV_VENV/bin/activate"'
alias ipy='"$DEV_VENV/bin/ipython"'
alias devpy='"$DEV_VENV/bin/python"'

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

# Completion for the git aliases. `compdef <func> <alias>=<command>` completes
# the alias as though the real command had been typed. Replaces the
# __git_complete calls that used to live in .bash_profile.
compdef _git gs=git-status
compdef _git gns=git-diff
compdef _git gd=git-diff
compdef _git gdc=git-diff
compdef _git gm=git-merge
compdef _git gma=git-merge
compdef _git gcp=git-commit
compdef _git gcq=git-commit

# ------------------------------------------------------------ gcloud auth ----

# Checks GCP auth once per interactive shell and offers to re-authenticate.
# Symlinked in by install.sh; guarded so a partially provisioned machine does
# not error. Knobs: GCLOUD_AUTH_CHECK, GCLOUD_AUTH_MODE, GCLOUD_AUTH_THROTTLE.
[ -f "$HOME/gcloud-auth-check.sh" ] && . "$HOME/gcloud-auth-check.sh"
