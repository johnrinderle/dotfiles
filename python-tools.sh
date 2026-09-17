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
black       black
harlequin   harlequin
posting     posting
ruff        ruff
vd          visidata

# Editor- and CI-invoked linters. .vimrc wires ALE to flake8 and pylint, so
# both have to exist as commands on PATH, not as importable libraries.
flake8      flake8
pylint      pylint
mypy        mypy
bandit      bandit

# Project tooling, deliberately kept outside any single project environment.
pre-commit  pre-commit
poetry      poetry
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
        run uv tool install --force "$@"
    else
        run uv tool install "$@"
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

    have uv || die "uv not found; run install.sh (uv comes from the Brewfile)"

    # Cache the installed executables once rather than shelling out per tool.
    # uv tool list prints a "name vX.Y" line per tool followed by "- <exe>"
    # lines for each executable it provides.
    UV_TOOLS="$(uv tool list 2>/dev/null | sed -n 's/^- //p' || true)"

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
