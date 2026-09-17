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
    have uv || { warn "uv not found; run install.sh"; return 0; }
    load_pyenv || { warn "pyenv not found; skipping Python libraries"; return 0; }

    # Update the interpreter currently selected, rather than re-resolving
    # "latest stable": bumping the Python version is install.sh's job.
    local version prefix py
    version="$(pyenv global 2>/dev/null || true)"
    if [ -z "$version" ] || [ "$version" = "system" ]; then
        warn "pyenv global is '${version:-unset}'; run install.sh to pin a version"
        return 0
    fi
    prefix="$(pyenv prefix "$version" 2>/dev/null || true)"
    py="${prefix:+$prefix/bin/python}"
    if [ -z "$py" ] || [ ! -x "$py" ]; then
        warn "no usable interpreter for pyenv version $version; skipping libraries"
    else
        info "upgrading requirements.txt in $py"
        run uv pip install --python "$py" --upgrade -r "$REPO_DIR/requirements.txt"
    fi

    log "Python tools"
    run uv tool upgrade --all
    # Install tools added to python-tools.sh since the last run.
    DRY_RUN="$DRY_RUN" "$REPO_DIR/python-tools.sh" \
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
        dry "vim +'PlugUpdate --sync' +qa"
        return 0
    fi
    # PlugUpdate also installs plugins added to .vimrc since the last run.
    vim +'PlugUpdate --sync' +qa >/dev/null 2>&1 || warn "vim PlugUpdate reported an error"
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
