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
    # A renamed cask leaves its old name behind as a Caskroom *symlink*
    # (google-cloud-sdk -> gcloud-cli). Those are aliases, not drift.
    brew list --cask 2>/dev/null | while read -r c; do
        [ -L "$(brew --prefix)/Caskroom/$c" ] || printf '%s\n' "$c"
    done | sort -u > "$WORK/instc"
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
    load_local_bin
    resolve_uv || { warn "uv not found"; return 0; }

    "$REPO_DIR/python-tools.sh" --list | sort -u > "$WORK/want"

    # `uv tool list` prints a "<package> v<version>" line per tool, followed
    # by one "- <executable>" line per executable it provides. Flatten that
    # into "<package><TAB><executable>" pairs so a package can be matched by
    # any of its executables -- visidata provides `vd`, black provides
    # `blackd`, and python-tools.sh records whichever name is typed.
    "$UV" tool list 2>/dev/null | awk '
        /^[^ -]/ { pkg = $1; next }
        /^- /    { if (pkg != "") print pkg "\t" $2 }
    ' > "$WORK/pairs"
    cut -f1 "$WORK/pairs" | sort -u > "$WORK/have_pkgs"
    cut -f2 "$WORK/pairs" | sort -u > "$WORK/have_exes"

    local missing=0 extra=0 t
    while read -r t; do
        [ -n "$t" ] || continue
        grep -qxF "$t" "$WORK/have_exes" \
            || { note "  recorded but not installed: $t"; missing=1; }
    done < "$WORK/want"
    [ "$missing" = 0 ] && skip "every recorded tool is installed"

    # A package is unrecorded only when neither its own name nor ANY of the
    # executables it provides appears in python-tools.sh. The previous version
    # compared against the installed executables instead of the recorded ones,
    # which always matched and so never reported anything.
    local pkg exe
    while read -r pkg; do
        [ -n "$pkg" ] || continue
        if grep -qxF "$pkg" "$WORK/want"; then
            continue
        fi
        if awk -F'\t' -v p="$pkg" '$1 == p { print $2 }' "$WORK/pairs" \
            | grep -qxF -f "$WORK/want" 2>/dev/null; then
            continue
        fi
        note "  installed but not recorded in python-tools.sh: $pkg"
        extra=1
    done < "$WORK/have_pkgs"
    [ "$extra" = 0 ] && skip "no unrecorded tools"

    # Tools whose interpreter has been deleted keep a directory and a shim on
    # PATH but die with "bad interpreter". `uv tool list` omits them entirely,
    # so without this they are invisible -- neither installed nor unrecorded.
    local dir broken=0 name
    dir="$("$UV" tool dir 2>/dev/null || true)"
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        for name in "$dir"/*/; do
            [ -d "$name" ] || continue
            [ -x "$name/bin/python" ] && continue
            note "  broken (interpreter gone): $(basename "$name")"
            broken=1
        done
    fi
    [ "$broken" = 0 ] && skip "no broken tool environments"
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
    load_local_bin

    if resolve_uv; then
        local want cur
        if [ -f "$REPO_DIR/.python-version" ]; then
            want="$(tr -d '[:space:]' < "$REPO_DIR/.python-version")"
        else
            want="$(latest_stable_python || true)"
        fi
        cur="$("$HOME/.local/bin/python3" -V 2>/dev/null | awk '{print $2}' || true)"
        if [ -z "$cur" ]; then
            note "  no uv-managed python3 in ~/.local/bin; run install.sh"
        elif python_default_matches "$want"; then
            skip "Python $cur (matches $want)"
        else
            note "  default python3 is $cur, but $want is available; run install.sh"
        fi

        if [ -x "$DEV_VENV/bin/python" ]; then
            skip "scratch venv present at $DEV_VENV"
        else
            note "  scratch venv missing at $DEV_VENV; run install.sh"
        fi

        # pyenv and asdf were replaced by uv; flag leftovers so they can go.
        local leftover
        for leftover in pyenv asdf; do
            if have "$leftover"; then
                note "  $leftover is still installed but no longer used; see README"
            fi
        done
    else
        warn "uv not found"
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
