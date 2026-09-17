# Login-shell environment: PATH and exported variables, read once per login.
# Aliases, completions and anything else that only matters at a prompt live in
# .zshrc, which every interactive shell reads.

# The following lines were added by Docker Desktop to add commands to your PATH.
export PATH="$PATH:$HOME/.docker/bin"
# End of Docker Desktop section.

# Homebrew. Checks both prefixes so this works on Apple Silicon and Intel,
# and stays quiet on a machine where Homebrew is not installed yet.
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$_brew" ]; then
        eval "$("$_brew" shellenv)"
        break
    fi
done
unset _brew

# uv installs both tool shims and the default `python`/`python3` into
# ~/.local/bin, so this needs to come before Homebrew's Python.
export PATH="$HOME/.local/bin:$PATH"

# MySQL client, pinned to 8.4. Keg-only because it is a versioned formula, so
# its bin has to be added by hand. Supplies mysql, mysqldump, mysqladmin and
# mysql_config.
if [ -n "${HOMEBREW_PREFIX:-}" ] && [ -d "$HOMEBREW_PREFIX/opt/mysql-client@8.4/bin" ]; then
    export PATH="$HOMEBREW_PREFIX/opt/mysql-client@8.4/bin:$PATH"
fi

# The scratch Python environment built from requirements.txt. Deliberately not
# on PATH, so it cannot shadow the default python3; the dev/ipy/devpy aliases
# in .zshrc reach it.
export DEV_VENV="$HOME/.venvs/dev"

# Node. nvm's completion is bash-style and is loaded in .zshrc, which sets up
# bashcompinit first.
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Added by VRSE. Guarded so a machine without the checkout does not error on
# every new shell.
VRSE_SOURCEME="$HOME/src/github.com/vitalsource/vrse/SOURCEME"
[ -f "$VRSE_SOURCEME" ] && source "$VRSE_SOURCEME"

# Colourised output from ls and friends
export CLICOLOR=1

# Default editor is vim
export EDITOR=$(which vim)

# Other configuration
export CLOUDSDK_PYTHON_SITEPACKAGES=1
export PRE_COMMIT_ALLOW_NO_CONFIG=1
