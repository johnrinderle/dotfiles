#!/bin/bash
#
# Bootstrap or repair this machine's local environment.
#
# Idempotent: every step checks first and does nothing if already satisfied.
# Safe to re-run on a fully provisioned machine -- re-running repairs whatever
# is missing (including symlinks) and leaves everything else alone.
#
#   ./install.sh                 provision / repair
#   ./install.sh --dry-run       show what would change, change nothing
#   ./install.sh --force         refresh steps that are already satisfied
#   ./install.sh --only symlinks,pytools    run just those steps
#   ./install.sh --help
#
# Written for bash 3.2 (the /bin/bash macOS ships) so it runs before the
# Brewfile's modern bash is installed.

set -euo pipefail

# Resolve the repo directory even when invoked through a symlink.
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
    _dir="$(cd "$(dirname "$_self")" && pwd -P)"
    _self="$(readlink "$_self")"
    case "$_self" in /*) ;; *) _self="$_dir/$_self" ;; esac
done
REPO_DIR="$(cd "$(dirname "$_self")" && pwd -P)"

# shellcheck source=lib/common.sh
. "$REPO_DIR/lib/common.sh"

# Homebrew's implicit auto-update would mutate taps even during --dry-run.
# Updating is done explicitly (step_homebrew under --force, and update.sh).
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1

NVM_VERSION="v0.40.7"
VIM_PLUG_URL="https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"

ALL_STEPS="homebrew symlinks brew node python pydeps pytools vim"
ONLY=""

# ------------------------------------------------------------------ usage ----

usage() {
    cat <<USAGE
Bootstrap or repair this machine's local environment.

Every step checks first and does nothing if already satisfied, so this is
safe to re-run on a fully provisioned machine. Re-running repairs whatever
is missing (including symlinks) and leaves everything else alone.

Usage: install.sh [options]

  -n, --dry-run        Report what would change; change nothing.
  -f, --force          Refresh steps that are already satisfied: upgrade brew
                       packages, reinstall uv tools and Python libraries, and
                       replace conflicting files in \$HOME (backing them up
                       first). Also rebuilds the pinned Python from source,
                       which clears that version's site-packages -- the
                       libraries are reinstalled immediately afterwards.
                       Nothing is ever uninstalled.
      --only STEPS     Comma-separated subset of steps to run.
  -h, --help           Show this help.

Steps: $ALL_STEPS

Version pinning:
  .python-version      If present, use this Python instead of latest stable.
  .nvmrc               If present, use this Node instead of current LTS.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)   FORCE=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        --only)       shift; ONLY="${1:-}" ;;
        --only=*)     ONLY="${1#--only=}" ;;
        -h|--help)    usage; exit 0 ;;
        *)            printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# Validate --only up front so a typo fails immediately rather than silently
# running nothing.
if [ -n "$ONLY" ]; then
    for _want in $(printf '%s' "$ONLY" | tr ',' ' '); do
        _ok=0
        for _s in $ALL_STEPS; do
            [ "$_want" = "$_s" ] && _ok=1
        done
        [ "$_ok" = 1 ] || die "unknown step '$_want'; valid steps: $ALL_STEPS"
    done
fi

wanted() {
    [ -z "$ONLY" ] && return 0
    local s
    for s in $(printf '%s' "$ONLY" | tr ',' ' '); do
        [ "$s" = "$1" ] && return 0
    done
    return 1
}

# -------------------------------------------------------------- homebrew ----

step_homebrew() {
    log "Homebrew"
    if have brew || load_brew_env; then
        skip "already installed ($(brew --version | head -1))"
    else
        info "installing Homebrew"
        if dry_run; then
            dry "curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash"
        else
            NONINTERACTIVE=1 /bin/bash -c \
                "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            load_brew_env || die "Homebrew installed but 'brew' is still not on PATH"
        fi
    fi

    if forced && ! dry_run; then
        info "refreshing formula index"
        brew update
    fi
}

# --------------------------------------------------------------- symlinks ----

# $SYMLINKS is defined in lib/common.sh, shared with audit.sh.
step_symlinks() {
    log "Symlinks into $HOME"
    # Here-string, not a pipe: a pipe would run the loop in a subshell and
    # lose link_file's warning count.
    while read -r src dest; do
        [ -n "${src:-}" ] || continue
        link_file "$REPO_DIR/$src" "$HOME/$dest"
    done <<< "$SYMLINKS"
}

# ------------------------------------------------------------ brew bundle ----

step_brew() {
    log "Brewfile packages"
    load_brew_env || { warn "Homebrew not available; skipping"; return 0; }

    # --no-upgrade scopes the check to "is it installed?". Without it, check
    # also reports merely-outdated packages as unsatisfied, which never
    # matches the default install below and defeats the skip.
    if dry_run; then
        brew bundle check --file "$REPO_DIR/Brewfile" --no-upgrade --verbose || true
        return 0
    fi

    if brew bundle check --file "$REPO_DIR/Brewfile" --no-upgrade >/dev/null 2>&1 && ! forced; then
        skip "all Brewfile entries already installed"
        return 0
    fi

    # --no-upgrade installs what is missing and leaves already-installed
    # packages at their current version; --force opts into upgrading them.
    if forced; then
        brew bundle install --file "$REPO_DIR/Brewfile"
    else
        brew bundle install --file "$REPO_DIR/Brewfile" --no-upgrade
    fi
}

# ------------------------------------------------------------------- node ----

step_node() {
    log "Node.js (nvm)"

    if [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ] && ! forced; then
        skip "nvm already installed"
    else
        info "installing nvm $NVM_VERSION"
        if dry_run; then
            dry "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash"
        else
            # The installer appends shell config; PROFILE=/dev/null keeps it
            # out of the tracked .zprofile, which already wires nvm up.
            PROFILE=/dev/null bash -c \
                "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash"
        fi
    fi

    if ! load_nvm; then
        if dry_run; then
            dry "nvm install <lts>  &&  nvm alias default <lts>"
            return 0
        fi
        warn "nvm could not be loaded; skipping Node install"
        return 0
    fi

    # Pin via .nvmrc when present, otherwise track the current LTS.
    local want desc
    if [ -f "$REPO_DIR/.nvmrc" ]; then
        want="$(tr -d '[:space:]' < "$REPO_DIR/.nvmrc")"
        desc="$want (pinned by .nvmrc)"
    else
        want="lts/*"
        desc="current LTS"
    fi

    local resolved
    resolved="$(nvm version "$want" 2>/dev/null || true)"
    if [ -z "$resolved" ] || [ "$resolved" = "N/A" ] || forced; then
        info "installing Node $desc"
        run nvm install "$want"
        resolved="$(nvm version "$want" 2>/dev/null || true)"
    else
        skip "Node $resolved already installed ($desc)"
    fi

    local current
    current="$(nvm version default 2>/dev/null || true)"
    if [ "$current" != "$resolved" ] || forced; then
        info "setting default Node alias to $want ($resolved)"
        run nvm alias default "$want"
    else
        skip "default Node alias already $current"
    fi
}

# ----------------------------------------------------------------- python ----

# Latest stable CPython that pyenv can build. Exactly-three-component versions
# only, which filters out pre-releases (3.15.0a1), free-threaded builds
# (3.14.0t) and the non-CPython distributions (pypy, anaconda, graalpy).
latest_stable_python() {
    pyenv install --list 2>/dev/null \
        | tr -d '[:blank:]' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -1
}

# Set by step_python, consumed by step_pydeps.
PY_VERSION=""

resolve_py_version() {
    if [ -f "$REPO_DIR/.python-version" ]; then
        PY_VERSION="$(tr -d '[:space:]' < "$REPO_DIR/.python-version")"
        info "target $PY_VERSION (pinned by .python-version)"
    else
        PY_VERSION="$(latest_stable_python)"
        [ -n "$PY_VERSION" ] || die "could not determine the latest stable Python from 'pyenv install --list'"
        info "target $PY_VERSION (latest stable)"
    fi
}

step_python() {
    log "Python (pyenv)"
    load_brew_env || true   # pyenv comes from Homebrew
    if ! load_pyenv; then
        if dry_run; then
            dry "pyenv install <latest stable>  &&  pyenv global <latest stable>"
            return 0
        fi
        warn "pyenv not found (it comes from the Brewfile); skipping"
        return 0
    fi

    resolve_py_version

    if pyenv versions --bare 2>/dev/null | grep -qxF "$PY_VERSION" && ! forced; then
        skip "Python $PY_VERSION already built"
    else
        info "building Python $PY_VERSION (this takes a few minutes)"
        if forced; then
            # --force rebuilds from source and discards this version's
            # site-packages; the pydeps step reinstalls them afterwards.
            info "--force: rebuilding, which clears its installed packages"
            run pyenv install --force "$PY_VERSION"
        else
            run pyenv install --skip-existing "$PY_VERSION"
        fi
    fi

    local current
    current="$(pyenv global 2>/dev/null || true)"
    if [ "$current" = "$PY_VERSION" ] && ! forced; then
        skip "pyenv global already $PY_VERSION"
    else
        info "setting pyenv global to $PY_VERSION (was ${current:-unset})"
        run pyenv global "$PY_VERSION"
    fi
}

# ------------------------------------------------- python libraries (uv) ----

# uv must be the Homebrew-managed one. A stray copy from the standalone
# installer in ~/.local/bin shadows it and goes stale silently.
UV_CHECKED=0
check_uv() {
    if ! have uv; then
        # Only warn once even though two steps depend on uv.
        [ "$UV_CHECKED" = 1 ] && return 1
        UV_CHECKED=1
        warn "uv not found (it comes from the Brewfile); skipping"
        return 1
    fi
    if [ "$UV_CHECKED" = 0 ]; then
        UV_CHECKED=1
        case "$(command -v uv)" in
            "$HOME"/.local/bin/uv)
                warn "uv resolves to ~/.local/bin/uv, not Homebrew's; that copy is unmanaged and will drift. Remove it with: rm -f ~/.local/bin/uv ~/.local/bin/uvx"
                ;;
        esac
    fi
    return 0
}

step_pydeps() {
    log "Python libraries (requirements.txt)"
    load_brew_env || true   # uv comes from Homebrew
    check_uv || return 0

    # BUG: resolve_py_version dies when it cannot read 'pyenv install --list'.
    # Without pyenv there is no interpreter to target, so skip cleanly instead.
    if ! load_pyenv; then
        warn "pyenv not found; cannot choose an interpreter for requirements.txt"
        return 0
    fi
    [ -n "$PY_VERSION" ] || resolve_py_version

    # Install into the interpreter this script pins, named explicitly. The old
    # 'uv pip install --system' resolved to whatever pyenv global happened to
    # be, which silently targeted the wrong Python.
    local prefix py=""
    prefix="$(pyenv prefix "$PY_VERSION" 2>/dev/null || true)"
    [ -n "$prefix" ] && py="$prefix/bin/python"
    if [ -z "$py" ] || [ ! -x "$py" ]; then
        if dry_run; then
            dry "uv pip install --python <pyenv $PY_VERSION> -r requirements.txt"
            return 0
        fi
        warn "Python $PY_VERSION is not installed; skipping (run the 'python' step first)"
        return 0
    fi

    info "target interpreter: $py"
    if forced; then
        run uv pip install --python "$py" --upgrade --reinstall -r "$REPO_DIR/requirements.txt"
    else
        # uv is a no-op when the requirements are already satisfied.
        run uv pip install --python "$py" -r "$REPO_DIR/requirements.txt"
    fi
}

# ----------------------------------------------------- python tools (uv) ----

step_pytools() {
    log "Python tools (python-tools.sh)"
    load_brew_env || true   # uv comes from Homebrew
    check_uv || return 0
    # Called directly, not through run(): python-tools.sh honours DRY_RUN
    # itself and prints per-tool detail that run() would hide.
    DRY_RUN="$DRY_RUN" FORCE="$FORCE" "$REPO_DIR/python-tools.sh" \
        || warn "python-tools.sh exited non-zero"
}

# -------------------------------------------------------------- vim-plug ----

step_vim() {
    log "vim-plug"
    local dest="$HOME/.vim/autoload/plug.vim"
    if [ -f "$dest" ] && ! forced; then
        skip "already installed at $dest"
    else
        info "downloading vim-plug"
        if dry_run; then
            dry "curl -fLo $dest --create-dirs $VIM_PLUG_URL"
        else
            curl -fLo "$dest" --create-dirs "$VIM_PLUG_URL"
        fi
    fi

    # Plugin install/update is update.sh's job; do it here too so a fresh
    # machine ends up with a working vim.
    if have vim; then
        if dry_run; then
            dry "vim +'PlugInstall --sync' +qa"
        else
            info "installing vim plugins"
            vim +'PlugInstall --sync' +qa >/dev/null 2>&1 || warn "vim PlugInstall reported an error"
        fi
    else
        skip "vim not on PATH yet; plugins will install on the next update.sh"
    fi
}

# ------------------------------------------------------------------- main ----

main() {
    if dry_run; then
        log "DRY RUN -- no changes will be made"
    fi

    for step in $ALL_STEPS; do
        wanted "$step" || continue
        "step_$step"
    done

    printf '\n'
    if [ "$DOTFILES_WARNINGS" -gt 0 ]; then
        log "Done, with $DOTFILES_WARNINGS warning(s) above."
    else
        log "Done."
    fi
    if ! dry_run; then
        info "Open a new shell (or 'exec zsh') to pick up PATH changes."
    fi
}

main
