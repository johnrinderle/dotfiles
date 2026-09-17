#!/bin/bash
#
# Update everything this repo manages, in place.
#
#   ./update.sh              update all package managers
#   ./update.sh --dry-run    report what would be updated
#
# Division of labour: update.sh upgrades what is already installed.
# install.sh is what installs missing things and moves the pinned Python and
# Node versions forward. Run "install.sh --only symlinks" to repair symlinks.

set -euo pipefail

# Resolve the repo directory even when invoked via the ~/update.sh symlink.
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
    _dir="$(cd "$(dirname "$_self")" && pwd -P)"
    _self="$(readlink "$_self")"
    case "$_self" in /*) ;; *) _self="$_dir/$_self" ;; esac
done
REPO_DIR="$(cd "$(dirname "$_self")" && pwd -P)"

# shellcheck source=lib/common.sh
. "$REPO_DIR/lib/common.sh"

usage() {
    cat <<'USAGE'
Update everything this repo manages.

Usage: update.sh [options]

  -n, --dry-run    Report what would be updated; update nothing.
  -h, --help       Show this help.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1
# Updating happens explicitly below; no implicit auto-update, so --dry-run
# stays genuinely read-only.
export HOMEBREW_NO_AUTO_UPDATE=1

# --------------------------------------------------------------- homebrew ----

update_brew() {
    log "Homebrew"
    load_brew_env || { warn "Homebrew not found; skipping"; return 0; }

    run brew update
    # Pick up entries added to the Brewfile since the last run. Read from the
    # repo directly so a stale copy in $HOME cannot be used by mistake.
    run brew bundle install --file "$REPO_DIR/Brewfile"
    # NOTE: 'brew upgrade -y' used to live here. There is no -y flag, so with
    # 'set -e' it aborted the script and nothing below this line ever ran.
    run brew upgrade
    run brew cleanup --prune=all
}

# ----------------------------------------------------------------- python ----

update_python() {
    log "Python"
    load_brew_env || true
    load_local_bin
    if ! resolve_uv; then
        warn "uv not found; run install.sh"
        return 0
    fi

    # Move the default Python to its latest patch release. Changing the minor
    # series is install.sh's job, not an update.
    run "$UV" python upgrade

    # Refresh the scratch environment built from requirements.txt.
    if [ -x "$DEV_VENV/bin/python" ]; then
        info "upgrading requirements.txt in $DEV_VENV"
        run "$UV" pip install --python "$DEV_VENV/bin/python" \
            --upgrade -r "$REPO_DIR/requirements.txt"
    else
        warn "$DEV_VENV does not exist; run install.sh"
    fi

    log "Python tools"
    run "$UV" tool upgrade --all
    # Install tools added to python-tools.sh since the last run.
    DRY_RUN="$DRY_RUN" UV="$UV" "$REPO_DIR/python-tools.sh" \
        || warn "python-tools.sh exited non-zero"
}

# ------------------------------------------------------------------- node ----

update_node() {
    log "Node.js"
    if ! load_nvm; then
        warn "nvm not found; skipping Node"
        return 0
    fi
    if [ "$(nvm version default 2>/dev/null || true)" = "N/A" ]; then
        warn "no default Node; run install.sh"
        return 0
    fi
    run nvm use default
    run npm install -g npm@latest
    run npm update -g
}

# -------------------------------------------------------------------- vim ----

update_vim() {
    log "vim plugins"
    if [ ! -f "$HOME/.vim/autoload/plug.vim" ]; then
        warn "vim-plug is not installed; run install.sh"
        return 0
    fi
    have vim || { warn "vim not found; skipping"; return 0; }
    if dry_run; then
        dry "vim +'PlugUpdate --sync' +qa  &&  vim +PlugClean! +qa"
        return 0
    fi
    # PlugUpdate installs plugins added to .vimrc; PlugClean! removes ones
    # taken out of it, which otherwise linger in ~/.vim/plugged forever.
    vim +'PlugUpdate --sync' +qa >/dev/null 2>&1 || warn "vim PlugUpdate reported an error"
    vim +'PlugClean!' +qa >/dev/null 2>&1 || warn "vim PlugClean reported an error"
}

# ------------------------------------------------------------------- main ----

dry_run && log "DRY RUN -- no changes will be made"

update_brew
update_python
update_node
update_vim

printf '\n'
if [ "$DOTFILES_WARNINGS" -gt 0 ]; then
    log "Done, with $DOTFILES_WARNINGS warning(s) above."
else
    log "Done."
fi
