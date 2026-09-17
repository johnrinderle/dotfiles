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

### Version pinning

By default `install.sh` tracks the latest stable CPython and the current Node
LTS. To pin instead, commit either file:

| File | Effect |
| --- | --- |
| `.python-version` | Use this Python instead of latest stable. |
| `.nvmrc` | Use this Node instead of current LTS. |

`update.sh` deliberately does **not** change these. It updates packages within
the selected runtimes; moving to a new Python or Node is `install.sh`'s job.

## What gets installed

| Manifest | Contents | Installed by |
| --- | --- | --- |
| `Brewfile` | Formulae and casks | `brew bundle` |
| `python-tools.sh` | Python CLI applications, each isolated | `uv tool install` |
| `requirements.txt` | Python libraries to `import` | `uv pip install` |
| `.vimrc` | vim plugins | vim-plug |

Applications belong in the `Brewfile` or `python-tools.sh`. `requirements.txt`
is only for libraries you `import`. See
[docs/python-packages.md](docs/python-packages.md) for the reasoning and a
review of the current library set.

### Files symlinked into `$HOME`

`.bash_profile`, `.vimrc`, `.zprofile`, `Brewfile`, `requirements.txt`,
`python-tools.sh`, `update.sh`.

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

To fold everything currently installed into the Brewfile:

```bash
brew bundle dump --describe --force --file Brewfile
```

Review that diff by hand — `dump` records everything, including things you
installed once to try out and do not want on the next machine.
