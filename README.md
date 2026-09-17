# dotfiles

Local environment for macOS. Three jobs:

1. **Install** — bring a new computer or fresh OS install up to working state.
2. **Update** — keep the installed software current.
3. **Record** — a durable, readable record of what is installed and why.

## Usage

```bash
git clone git@github.com:johnrinderle/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh --dry-run    # see what it would do
./install.sh              # do it
```

Everything is idempotent: run `install.sh` on a machine that is already set up
and it reports what is already present, changes nothing else, and repairs
anything missing — including symlinks.

| Script | Purpose |
| --- | --- |
| `install.sh` | Provision or repair. Installs what is missing, pins the Python and Node versions. |
| `update.sh` | Upgrade what is already installed. |
| `audit.sh` | Read-only. Report drift between this repo and the machine. |
| `python-tools.sh` | The list of Python CLI applications; run by the other two. |
| `lib/common.sh` | Shared helpers. Sourced, not run. |

### install.sh

```
-n, --dry-run     Report what would change; change nothing.
-f, --force       Refresh steps that are already satisfied.
    --only STEPS  Comma-separated subset, e.g. --only symlinks,pytools
-h, --help
```

Steps, in order: `homebrew symlinks brew node python pydeps pytools vim`

`--force` means "refresh what is already satisfied": upgrade brew packages,
rebuild the pinned Python, reinstall uv tools and Python libraries, and replace
conflicting files in `$HOME`. It never uninstalls anything, and it backs up any
file it replaces to `<name>.backup-<timestamp>`.

Without `--force`, a file in `$HOME` that is not the expected symlink is left
alone and reported, so a hand-edited file is never silently destroyed. Missing
and broken symlinks are always repaired, since doing so discards nothing.

### Runtimes

Python is managed by **uv**, Node by **nvm**. pyenv and asdf are no longer
used — see [docs/python-packages.md](docs/python-packages.md) for the uv
commands and for how to remove the leftovers.

By default `install.sh` tracks the latest stable CPython series and the
current Node LTS. To pin instead, commit either file:

| File | Effect |
| --- | --- |
| `.python-version` | Use this Python instead of the latest stable series. Also honoured by uv inside any project. |
| `.nvmrc` | Use this Node instead of current LTS. |

`update.sh` deliberately does **not** move these. It updates packages and
patch releases within the selected runtimes; changing to a new Python or Node
series is `install.sh`'s job.

Per-project Python versions need nothing from this repo: drop a
`.python-version` in the project and uv downloads that version on demand.

## What gets installed

| Manifest | Contents | Installed by |
| --- | --- | --- |
| `Brewfile` | Formulae and casks | `brew bundle` |
| `python-tools.sh` | Python CLI applications, each isolated | `uv tool install` |
| `requirements.txt` | Baseline Python libraries, into `~/.venvs/dev` | `uv pip install` |
| `.vimrc` | vim plugins | vim-plug |

Applications belong in the `Brewfile` or `python-tools.sh`. `requirements.txt`
is only for libraries you `import`, and only for baseline ones — a project
gets its own venv. See [docs/python-packages.md](docs/python-packages.md).

The scratch environment is not on `PATH`, so it cannot shadow the default
`python3`. Reach it deliberately:

```bash
dev      # activate ~/.venvs/dev
ipy      # IPython inside it
devpy    # its python, without activating
```

### Editor

`vim` and `nvim` share one configuration: `nvim-init.vim` is symlinked to
`~/.config/nvim/init.vim` and sources `~/.vimrc`. Python support is ruff (all
diagnostics and formatting) plus pylsp (completion, go-to-definition, hover,
references, rename), both driven by ALE.

### Files symlinked into `$HOME`

`.vimrc`, `.zprofile`, `Brewfile`, `requirements.txt`, `python-tools.sh`,
`update.sh`, and `nvim-init.vim` → `~/.config/nvim/init.vim`.

The shell is zsh; there is no bash profile.

The list lives in `$SYMLINKS` in `lib/common.sh`, shared by `install.sh` and
`audit.sh`.

> Because `~/Brewfile` is a symlink into this repo, anything that writes to it
> writes into the repo. That is what you want for `brew bundle dump`, but it
> means an editor "save as" on `~/Brewfile` edits version-controlled content.

## Keeping the record honest

`audit.sh` reports what is installed but not recorded, and what is recorded but
not installed. It exits non-zero when it finds drift, so it works from cron.

```bash
./audit.sh
```

### Pending cleanup

Dropping something from a manifest never uninstalls it, so these are left for
you to run. `audit.sh` keeps reporting them until they are gone.

Replaced by uv, and no longer referenced anywhere:

```bash
brew uninstall pyenv asdf && rm -rf ~/.pyenv ~/.asdf
```

Not wanted (`bash-completion` because the shell is zsh):

```bash
brew uninstall pandoc htop typst bash-completion
```

Superseded Python tools — `ruff format` replaces black:

```bash
uv tool uninstall black
```

Judgement calls, not done:

| Package | Question |
| --- | --- |
| `mysql`, `mysql-client` | Only `mysql-client@8.0` is on `PATH`. Drop the other two unless you run a local MySQL server. |
| `python@3.11`, `python@3.12` | Homebrew Pythons, redundant now that uv manages Python. Nothing depends on either (142 MB). |
| `docutils` | reStructuredText tooling; nothing depends on it, and pandoc is gone. |
| `mactop` | Apple Silicon system monitor — the same category as the `htop` that was removed. |
| `sslyze` | Installed as a uv tool but unrecorded, and overlaps `sslscan`. Add it to `python-tools.sh` or remove it. |

To fold everything currently installed into the Brewfile:

```bash
brew bundle dump --describe --force --file Brewfile
```

Review that diff by hand — `dump` records everything, including things you
installed once to try out and do not want on the next machine.
