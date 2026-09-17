# Python setup: how it works and why

## 1. Everything Python runs through uv

`uv` replaces pyenv and asdf entirely.

| Need | Command |
| --- | --- |
| Install a Python and make it the default | `uv python install 3.14 --default` |
| Pin a version for one project | `uv python pin 3.12` (writes `.python-version`) |
| Pin the machine-wide default | `uv python pin --global 3.14` |
| See what is installed and available | `uv python list` |
| Move to the latest patch release | `uv python upgrade` |
| Remove one | `uv python uninstall 3.12` |
| Find the interpreter for a request | `uv python find 3.12` |

Global and per-project coexist, which is the thing pyenv was doing:

- `uv python install <v> --default` puts real `python` and `python3`
  executables in `~/.local/bin`. That is the machine default.
- A project with its own `.python-version` wins inside that directory, and
  **uv downloads the version on demand** if it is missing. No `pyenv install`
  step, no waiting for a source build — these are prebuilt distributions.
- `uv venv`, `uv run` and `uv sync` all honour the project's pin
  automatically.

So the answer to "can I have a global install plus project-specific installs"
is yes, and it needs less bookkeeping than pyenv did: projects declare what
they want and uv fetches it.

`install.sh` resolves the newest stable CPython *series* (e.g. `3.14`) and
leaves the patch level to uv, so `uv python upgrade` can move it forward
without the repo needing to know. Commit a `.python-version` here to pin
instead.

`--default` is still flagged experimental upstream. If it ever regresses, the
fallback is `uv python pin --global` plus `~/.local/bin` on `PATH`.

### Leftovers to remove

pyenv and asdf are no longer referenced. Once you are happy with the new
setup:

```bash
brew uninstall pyenv asdf
rm -rf ~/.pyenv ~/.asdf
```

That reclaims the six Python builds under `~/.pyenv/versions`. `audit.sh`
flags both until they are gone.

## 2. Three places Python software lives

| What it is | Where | Why |
| --- | --- | --- |
| A command you type (`ruff`, `poetry`, `pylsp`) | `python-tools.sh` → `uv tool install` | Each gets an isolated environment, so their dependencies cannot conflict. Executables still land on `PATH`. |
| A baseline library for scripts and ad-hoc work | `requirements.txt` → `~/.venvs/dev` | One environment, always there, nothing to set up first. |
| A library a project needs | The project's own venv (`uv add` / `uv sync`) | Pinned with the project, not with the laptop. |
| A one-off script's dependency | `uv run --with httpx script.py`, or PEP 723 inline metadata | No install at all. |

### Why `requirements.txt` goes into a venv

It used to be installed with `uv pip install --system`, which resolved to
whatever `pyenv global` pointed at — in practice **Python 3.9.16**, not the
3.14 that `install.sh` intended. The destination also moved silently whenever
`pyenv global` changed.

A dedicated venv fixes both, and it is the only correct target now: uv ignores
interpreters that are not in a virtual environment unless given `--system`,
and its managed Python installs are not meant to be written into.

```bash
dev      # activate ~/.venvs/dev
ipy      # IPython inside it
devpy    # its python, without activating
```

`pynvim` lives here too, and `nvim-init.vim` sets `g:python3_host_prog` to
this venv. Previously the provider tracked `pyenv global` and broke silently
every time the default Python moved.

## 3. What is in requirements.txt, and why

The bar is: *would I be mildly annoyed to have to install this before writing
five lines?* It is not meant to cover what a project needs — that is what a
project venv is for.

19 direct packages, 53 with transitive dependencies.

| Group | Packages |
| --- | --- |
| HTTP and web | `httpx`, `requests`, `beautifulsoup4`, `lxml`, `websockets` |
| Data and formats | `numpy`, `openpyxl`, `pyyaml`, `xmltodict`, `python-dateutil`, `unidecode` |
| Databases | `pymongo`, `pymysql` |
| Validation, config, auth | `pydantic`, `python-dotenv`, `pyjwt` |
| Console | `ipython`, `rich` |
| Editor | `pynvim` |

### Added

| Package | Why |
| --- | --- |
| `httpx` | Sync and async in one API, and what most current examples assume. `requests` stays because everything older assumes it. |
| `rich` | Tables, progress bars, syntax highlighting, readable tracebacks. This is what `pastel` was gesturing at, done properly. |
| `python-dotenv` | Reads a `.env` without hand-rolling a parser. Replaces `prettyconf`. |
| `pymysql` | Replaces `mysqlclient` — see below. |

### Removed

| Package | Why |
| --- | --- |
| `mysqlclient` | Ships **Windows-only wheels**; on macOS it compiles against libmysqlclient and needs `mysql_config`. It worked only because `mysql-client@8.0` happened to be installed. `pymysql` is pure Python and needs no toolchain. |
| `pytest`, `ipdb`, `types-requests` | Only useful inside the environment holding the code under test. A global `pytest` run against a project venv is a classic source of confusing `ImportError`s. |
| `pastel` | A console-colour library, not an interactive tool; almost certainly arrived as a transitive dependency of poetry. `rich` covers the need. |
| `prettyconf` | Niche. `python-dotenv` and `os.environ` cover it. |
| `pyopenssl` | Legacy shim over `cryptography`, which arrives as a dependency anyway. |
| `github3.py` | Last meaningful release 2022. The `gh` CLI covers most of it; `PyGithub` is better maintained if a library is needed. |
| `isodate` | `datetime.fromisoformat` handles ISO 8601 as of 3.11. Only durations are left, which is niche. |
| `websocket-client` | The sync counterpart to `websockets`; keeping both means remembering which is which. |
| `xlsxwriter` | Write-only; `openpyxl` reads *and* writes. Add it back per project if you need charts or very large sheets. |
| `pytz` | Superseded by stdlib `zoneinfo` (3.9+). |
| `nodeenv` | Node inside a Python venv; nvm handles Node. |
| `pip-review`, `pipenv` | Superseded by uv. |
| `sslyze` | A CLI, not a library, and the Brewfile already has `sslscan`. |
| `autopep8`, `isort`, `pycodestyle`, `pyflakes`, `pydocstyle`, `pylama`, `pep8`, `flake8`, `pylint`, `black` | All superseded by ruff. See the editor section. `pep8` was abandoned in 2016. |
| `python-lsp-server` | Still used, but as a command — it moved to `python-tools.sh`. |

### Further candidates, not added

Say the word and these go in; each is genuinely useful but none felt like a
baseline:

- **`pandas`** — the obvious one. Left out because `duckdb`, `visidata` and
  `miller` are already in the Brewfile and cover most ad-hoc table work, and
  it is a heavy dependency for a default environment.
- **`duckdb`** (the Python package) — excellent for querying CSV/Parquet
  in-process. Strong candidate given the CLI is already installed.
- **`jinja2`** — templating for generated files and prompts.
- **`tenacity`** — retry/backoff, which is otherwise always hand-rolled.
- **`tabulate`** — superseded by `rich` for most uses.

## 4. The editor: ruff plus one LSP

`.vimrc` used to drive ALE with flake8 and pylint, which is the only reason
that whole family of packages was installed. It is now two tools:

- **ruff** — all diagnostics, plus formatting and import sorting
  (`ale_fixers` runs `ruff` then `ruff_format` on save)
- **pylsp** — the LSP features: completion, go-to-definition, hover,
  find-references, rename

pylsp's own bundled linters are disabled in `g:ale_python_pylsp_config`, so
diagnostics come from ruff alone and nothing is reported twice.

Ten packages collapse to two, and you gain go-to-definition.

| Mapping | Action |
| --- | --- |
| `<leader>gd` / `<leader>gt` | Go to definition / type definition |
| `<leader>gr` | Find references |
| `<leader>rn` | Rename symbol |
| `<leader>ai` | Auto-import the symbol under the cursor |
| `<leader>tb` | Symbol search |
| `K` | Hover documentation |
| `[d` / `]d` | Previous / next diagnostic |

ALE has native uv support, so `g:ale_python_auto_uv` makes it run a project's
own pinned ruff when the project is a uv project, falling back to the global
uv tools otherwise.

`vim` and `nvim` share one configuration: `nvim-init.vim` is symlinked to
`~/.config/nvim/init.vim` and sources `~/.vimrc`. Both use `~/.vim/plugged`,
which needs `call plug#begin('~/.vim/plugged')` to be explicit — with no
argument vim-plug picks a *different* default under nvim and the two would not
share plugins.

### If you want to go further

`ty`, Astral's type checker, is in `python-tools.sh` commented out and is
supported by current ALE. It is fast and from the same people as ruff and uv,
but still early. Enabling it would also let `mypy` go.

## 5. Ideas not acted on

**Lock the library set.** For a reproducible record rather than just a list:

```bash
uv pip compile requirements.txt -o requirements.lock   # commit this
uv pip sync requirements.lock --python ~/.venvs/dev/bin/python
```

`uv pip sync` also *removes* anything not in the lockfile, so the venv matches
the record exactly instead of merely containing it.

**Or make it a project.** A `pyproject.toml` plus `uv sync` would give the
scratch environment a real lockfile and let `uv` manage it as a project. That
is the most idiomatic uv setup, at the cost of `requirements.txt` no longer
being a plain readable list.
