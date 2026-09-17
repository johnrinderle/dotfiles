#!/bin/bash
#
# Report drift between what this repo records and what is actually installed.
# Read-only: this script never changes anything.
#
# Serves the "durable record" purpose of this repo. If something you rely on
# shows up under "not recorded", add it to the Brewfile or python-tools.sh so
# a fresh machine gets it too.
#
# Exits non-zero when drift is found, so it is usable from a cron job.

set -euo pipefail

_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
    _dir="$(cd "$(dirname "$_self")" && pwd -P)"
    _self="$(readlink "$_self")"
    case "$_self" in /*) ;; *) _self="$_dir/$_self" ;; esac
done
REPO_DIR="$(cd "$(dirname "$_self")" && pwd -P)"

# shellcheck source=lib/common.sh
. "$REPO_DIR/lib/common.sh"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DRIFT=0
note() { DRIFT=$((DRIFT + 1)); printf '    %s\n' "$*"; }

# ------------------------------------------------------------------- brew ----

audit_brew() {
    log "Homebrew formulae"
    load_brew_env || { warn "Homebrew not found"; return 0; }

    # Strip any tap prefix so "mongodb/brew/mongodb-database-tools" compares
    # against the bare formula name that brew reports.
    grep -E '^brew "' "$REPO_DIR/Brewfile" \
        | sed 's/^brew "//; s/".*//; s#.*/##' | sort -u > "$WORK/bf"
    brew leaves --installed-on-request 2>/dev/null \
        | sed 's#.*/##' | sort -u > "$WORK/inst"

    local n
    n="$(comm -13 "$WORK/bf" "$WORK/inst" | wc -l | tr -d ' ')"
    if [ "$n" = 0 ]; then
        skip "every explicitly installed formula is recorded"
    else
        info "installed on request but NOT in the Brewfile:"
        # Piped loop runs in a subshell, so print here and count once outside.
        comm -13 "$WORK/bf" "$WORK/inst" | while read -r f; do printf '      %s\n' "$f"; done
        DRIFT=$((DRIFT + n))
    fi

    log "Homebrew casks"
    grep -E '^cask "' "$REPO_DIR/Brewfile" | sed 's/^cask "//; s/".*//' | sort -u > "$WORK/bfc"
    brew list --cask 2>/dev/null | sort -u > "$WORK/instc"
    n="$(comm -13 "$WORK/bfc" "$WORK/instc" | wc -l | tr -d ' ')"
    if [ "$n" = 0 ]; then
        skip "every installed cask is recorded"
    else
        info "installed but NOT in the Brewfile:"
        comm -13 "$WORK/bfc" "$WORK/instc" | while read -r f; do printf '      %s\n' "$f"; done
        DRIFT=$((DRIFT + n))
    fi
}

# -------------------------------------------------------------- uv tools ----

audit_uv_tools() {
    log "uv tools"
    have uv || { warn "uv not found"; return 0; }

    "$REPO_DIR/python-tools.sh" --list | sort -u > "$WORK/want"
    # Top-level lines of `uv tool list` are "<package> v<version>".
    uv tool list 2>/dev/null | sed -n 's/^\([^ -][^ ]*\) v.*/\1/p' | sort -u > "$WORK/have_pkgs"
    uv tool list 2>/dev/null | sed -n 's/^- //p' | sort -u > "$WORK/have_exes"

    local missing=0 extra=0 t
    while read -r t; do
        grep -qxF "$t" "$WORK/have_exes" || { note "  recorded but not installed: $t"; missing=1; }
    done < "$WORK/want"
    [ "$missing" = 0 ] && skip "every recorded tool is installed"
    :

    while read -r t; do
        # A tool is "extra" when neither its package name nor any executable
        # it provides appears in python-tools.sh.
        if ! grep -qxF "$t" "$WORK/want"; then
            grep -qxF "$t" "$WORK/have_exes" && continue
            note "  installed but not recorded in python-tools.sh: $t"
            extra=1
        fi
    done < "$WORK/have_pkgs"
    [ "$extra" = 0 ] && skip "no unrecorded tools"
    return 0
}

# -------------------------------------------------------------- symlinks ----

audit_symlinks() {
    log "Symlinks"
    local ok=1 src dest
    while read -r src dest; do
        [ -n "${src:-}" ] || continue
        if [ ! -e "$HOME/$dest" ]; then
            note "  missing: ~/$dest"; ok=0
        elif [ ! -L "$HOME/$dest" ]; then
            note "  not a symlink: ~/$dest"; ok=0
        elif [ "$(resolve_path "$HOME/$dest")" != "$(resolve_path "$REPO_DIR/$src")" ]; then
            note "  points elsewhere: ~/$dest -> $(readlink "$HOME/$dest")"; ok=0
        fi
    done <<< "$SYMLINKS"
    [ "$ok" = 1 ] && skip "all symlinks correct"
    return 0
}

# ------------------------------------------------------------- versions ----

audit_versions() {
    log "Runtime versions"
    if load_pyenv; then
        local cur want
        cur="$(pyenv global 2>/dev/null || true)"
        if [ -f "$REPO_DIR/.python-version" ]; then
            want="$(tr -d '[:space:]' < "$REPO_DIR/.python-version")"
        else
            want="$(pyenv install --list 2>/dev/null | tr -d '[:blank:]' \
                | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
                | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
        fi
        if [ "$cur" = "$want" ]; then
            skip "Python $cur (current)"
        else
            note "  pyenv global is $cur, but $want is available; run install.sh"
        fi
    else
        warn "pyenv not found"
    fi

    if load_nvm; then
        local nd nl
        nd="$(nvm version default 2>/dev/null || true)"
        nl="$(nvm version 'lts/*' 2>/dev/null || true)"
        if [ "$nd" = "$nl" ]; then
            skip "Node $nd (current LTS)"
        else
            note "  default Node is $nd, LTS is $nl; run install.sh"
        fi
    else
        warn "nvm not found"
    fi
    return 0
}

# ------------------------------------------------------------------ main ----

audit_brew
audit_uv_tools
audit_symlinks
audit_versions

printf '\n'
if [ "$DRIFT" -gt 0 ]; then
    log "$DRIFT item(s) of drift found."
    exit 1
fi
log "No drift."
