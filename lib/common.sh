# shellcheck shell=bash
# Shared helpers for install.sh, update.sh and python-tools.sh.
# Sourced, never executed.
#
# Deliberately bash 3.2 compatible: /bin/bash on macOS is 3.2, and the
# bootstrap runs before the Brewfile's modern bash exists. No associative
# arrays, no mapfile, no ${var,,}.

# Guard against being sourced twice within one shell. (python-tools.sh runs as
# a separate process, so it sources this file fresh -- that is intended.)
if [ -n "${DOTFILES_COMMON_LOADED:-}" ]; then
    return 0
fi
DOTFILES_COMMON_LOADED=1

DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"

# ---------------------------------------------------------------- output ----

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _c_head=$'\033[1;34m'; _c_skip=$'\033[2m'; _c_warn=$'\033[33m'
    _c_fail=$'\033[31m';   _c_dry=$'\033[36m';  _c_off=$'\033[0m'
else
    _c_head=''; _c_skip=''; _c_warn=''; _c_fail=''; _c_dry=''; _c_off=''
fi

log()  { printf '%s==> %s%s\n' "$_c_head" "$*" "$_c_off"; }
info() { printf '    %s\n' "$*"; }
skip() { printf '    %s- %s%s\n' "$_c_skip" "$*" "$_c_off"; }
DOTFILES_WARNINGS=0
warn() {
    DOTFILES_WARNINGS=$((DOTFILES_WARNINGS + 1))
    printf '    %swarning: %s%s\n' "$_c_warn" "$*" "$_c_off" >&2
}
die()  { printf '    %serror: %s%s\n' "$_c_fail" "$*" "$_c_off" >&2; exit 1; }

# Quote a command for display without pulling in printf %q (bash 3.2 %q is
# available but produces noisier output than we want here).
_fmt_cmd() {
    local out='' arg
    for arg in "$@"; do
        case "$arg" in
            ''|*[!A-Za-z0-9_./=:@%+-]*) out="$out '$arg'" ;;
            *)                          out="$out $arg" ;;
        esac
    done
    printf '%s' "${out# }"
}

# run CMD [ARGS...] -- execute, or print under --dry-run.
# Only for simple commands and shell functions; no pipelines or redirection.
run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '    %s[dry-run] %s%s\n' "$_c_dry" "$(_fmt_cmd "$@")" "$_c_off"
        return 0
    fi
    "$@"
}

# Announce a mutating action that run() cannot express (pipelines, etc).
dry() {
    printf '    %s[dry-run] %s%s\n' "$_c_dry" "$*" "$_c_off"
}

have() { command -v "$1" >/dev/null 2>&1; }

forced() { [ "$FORCE" = 1 ]; }
dry_run() { [ "$DRY_RUN" = 1 ]; }

# ---------------------------------------------------------------- symlink ----

# The files this repo owns in $HOME, one "<repo path> <name in $HOME>" per
# line. Shared by install.sh (creates them) and audit.sh (verifies them).
SYMLINKS='
.bash_profile    .bash_profile
.vimrc           .vimrc
.zprofile        .zprofile
Brewfile         Brewfile
requirements.txt requirements.txt
python-tools.sh  python-tools.sh
update.sh        update.sh
'

# link_file SRC DEST -- make DEST an absolute symlink to SRC.
#
# Idempotency rules:
#   * DEST already resolves to SRC          -> no action (any link style)
#   * DEST missing                          -> created, always (even w/o --force)
#   * DEST is a conflicting link/file/dir   -> warn and skip, unless --force,
#                                              which backs it up first
#
# Links are written absolute so no external tool is needed during bootstrap,
# but an existing *relative* link that resolves to SRC is accepted as correct,
# which keeps links made by earlier versions of this script in place.
link_file() {
    local src="$1" dest="$2" backup removed_broken=0

    if [ ! -e "$src" ]; then
        warn "$src does not exist; not linking $dest"
        return 0
    fi

    # A symlink whose target no longer exists counts as "missing", not as a
    # conflict: dropping it destroys nothing, so repair it without --force.
    if [ -L "$dest" ] && [ ! -e "$dest" ]; then
        info "removing broken symlink $dest -> $(readlink "$dest")"
        run rm -f "$dest"
        removed_broken=1
    fi

    # removed_broken keeps --dry-run honest: the link is still on disk because
    # we did not really rm it, but the live run would have.
    if [ "$removed_broken" = 0 ] && { [ -L "$dest" ] || [ -e "$dest" ]; }; then
        if [ -L "$dest" ] && [ "$(resolve_path "$dest")" = "$(resolve_path "$src")" ]; then
            skip "$dest already links to $src"
            return 0
        fi
        if ! forced; then
            if [ -L "$dest" ]; then
                warn "$dest is a symlink to $(readlink "$dest"); re-run with --force to replace it"
            else
                warn "$dest already exists and is not a symlink; re-run with --force to replace it"
            fi
            return 0
        fi
        backup="$dest.backup-$(date +%Y%m%d%H%M%S)"
        info "backing up $dest -> $backup"
        run mv "$dest" "$backup"
    fi

    dry_run || info "linking $dest -> $src"
    run ln -sfn "$src" "$dest"
}

# resolve_path PATH -- absolute, symlink-resolved path. Works on bare macOS
# (no realpath/coreutils needed) and tolerates a missing final component.
resolve_path() {
    local target="$1" dir base
    dir="$(dirname "$target")"
    base="$(basename "$target")"
    if [ ! -d "$dir" ]; then
        printf '%s\n' "$target"
        return 0
    fi
    dir="$(cd "$dir" 2>/dev/null && pwd -P)" || { printf '%s\n' "$target"; return 0; }
    local hops=0
    while [ -L "$dir/$base" ]; do
        hops=$((hops + 1))
        if [ "$hops" -gt 40 ]; then
            # Symlink cycle; report what we have rather than looping forever.
            break
        fi
        target="$(readlink "$dir/$base")"
        case "$target" in
            /*) dir="$(dirname "$target")" ;;
            *)  dir="$(cd "$dir" && cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || break ;;
        esac
        dir="$(cd "$dir" 2>/dev/null && pwd -P)" || break
        base="$(basename "$target")"
    done
    printf '%s\n' "${dir%/}/$base"
}

# ------------------------------------------------------------ environment ----

# load_brew_env -- put brew on PATH for the rest of this script.
load_brew_env() {
    if have brew; then
        eval "$(brew shellenv)"
        return 0
    fi
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            eval "$("$candidate" shellenv)"
            return 0
        fi
    done
    return 1
}

# load_nvm -- source nvm into this shell so `nvm` is callable.
load_nvm() {
    NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    export NVM_DIR
    [ -s "$NVM_DIR/nvm.sh" ] || return 1
    # nvm.sh is not reliably `set -u` clean, and `set -e` makes its internal
    # probing fatal; relax both just for the source.
    local had_u=0 had_e=0
    case "$-" in *u*) had_u=1 ;; esac
    case "$-" in *e*) had_e=1 ;; esac
    set +u +e
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    local rc=$?
    [ "$had_u" = 1 ] && set -u
    [ "$had_e" = 1 ] && set -e
    return $rc
}

# load_pyenv -- put pyenv's root/shims on PATH for this shell.
load_pyenv() {
    have pyenv || return 1
    PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
    export PYENV_ROOT
    case ":$PATH:" in
        *":$PYENV_ROOT/shims:"*) ;;
        *) PATH="$PYENV_ROOT/shims:$PATH"; export PATH ;;
    esac
    return 0
}
