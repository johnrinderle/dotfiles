#!/bin/bash
#
# Standalone Python CLI applications, each installed by uv into its own
# isolated environment and exposed on PATH via ~/.local/bin.
#
# This file is the record of which tools belong on this machine. It is run by
# install.sh and update.sh, and can also be run on its own.
#
# Use this for anything invoked as a *command*. Use requirements.txt only for
# libraries you need to import. See docs/python-packages.md.

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

usage() {
    cat <<'USAGE'
Install the Python CLI applications recorded in this file, using uv.

Usage: python-tools.sh [options]

  -n, --dry-run    Report what would be installed; install nothing.
  -f, --force      Reinstall every tool, even those already present.
  -l, --list       Print the command name of each recorded tool and exit.
  -h, --help       Show this help.
USAGE
}

LIST_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)   FORCE=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -l|--list)    LIST_ONLY=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# One tool per line: "<command-on-PATH> <uv tool install arguments...>".
#
# The first field is the executable the tool provides, which is what gets
# tested for; it is not always the package name (visidata provides "vd").
# Extra uv arguments are allowed, e.g. "--with" for plugins the tool needs.
TOOLS='
harlequin   harlequin
posting     posting
vd          visidata

# Editor tooling. .vimrc drives ALE from these two: ruff for diagnostics and
# formatting, pylsp for the LSP features (completion, go-to-definition,
# hover, references, rename). Together they replace flake8, pylint, autopep8,
# isort, pycodestyle, pyflakes, pydocstyle, pylama and black.
ruff        ruff
pylsp       python-lsp-server

# Standalone checkers, run by hand rather than by the editor.
mypy        mypy
bandit      bandit

# Project tooling, deliberately kept outside any single project environment.
pre-commit  pre-commit
poetry      poetry

# The Astral type checker (same authors as ruff and uv), a possible future
# replacement for mypy here. Still early; uncomment to try it.
#ty         ty
'

install_tool() {
    local cmd="$1"
    shift

    # uv tool list is the authoritative check: a command can be on PATH from
    # brew or a stale venv without being a uv-managed tool.
    if printf '%s\n' "$UV_TOOLS" | grep -qxF "$cmd" && ! forced; then
        skip "$cmd"
        return 0
    fi

    if forced; then
        run "$UV" tool install --force "$@"
    else
        run "$UV" tool install "$@"
    fi
}

# Print just the command names, for audit.sh.
list_tools() {
    while read -r cmd _; do
        case "${cmd:-}" in
            ''|'#'*) continue ;;
        esac
        printf '%s\n' "$cmd"
    done <<< "$TOOLS"
}

main() {
    if [ "$LIST_ONLY" = 1 ]; then
        list_tools
        return 0
    fi

    # $UV may be passed in by install.sh; otherwise resolve it here. Prefers
    # Homebrew's uv over a stale standalone copy in ~/.local/bin.
    if [ -z "${UV:-}" ]; then
        load_brew_env || true
        resolve_uv || die "uv not found; run install.sh (uv comes from the Brewfile)"
    fi
    load_local_bin

    # Cache the installed executables once rather than shelling out per tool.
    # uv tool list prints a "name vX.Y" line per tool followed by "- <exe>"
    # lines for each executable it provides.
    UV_TOOLS="$("$UV" tool list 2>/dev/null | sed -n 's/^- //p' || true)"

    log "Python tools (uv tool)"
    while read -r cmd args; do
        case "${cmd:-}" in
            ''|'#'*) continue ;;
        esac
        # $args is intentionally unquoted so extra uv flags split into words.
        # shellcheck disable=SC2086
        install_tool "$cmd" $args
    done <<< "$TOOLS"
}

main
