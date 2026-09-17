# Python packages: review and recommendations

Feedback on `requirements.txt` — what is being installed, how useful it is, and
where each thing actually belongs.

## 1. The structural problem (fixed)

`update.sh` used to run:

```
uv pip install --system -r requirements.txt
```

`--system` means "install into whatever interpreter is on PATH rather than a
virtualenv". Under pyenv that resolves to `pyenv global`, which on this machine
was **3.9.16** — so all 45 packages were being installed into a Python from
2022, not the 3.14 that `install.sh` intended to pin. Worse, the destination
moved silently whenever `pyenv global` changed, so the "record of installed
software" described something other than reality.

Both scripts now name the interpreter explicitly:

```
uv pip install --python "$(pyenv prefix 3.14.7)/bin/python" -r requirements.txt
```

## 2. Where Python software should live

The single most useful change is to stop treating `requirements.txt` as a
catch-all. There are four distinct needs and only one of them is a flat
requirements file:

| What it is | Where it belongs | Why |
| --- | --- | --- |
| A command you type (`ruff`, `poetry`, `mypy`) | `python-tools.sh` → `uv tool install` | Each gets its own isolated env, so their dependencies can never conflict; executables are still linked onto `PATH`. |
| A library you `import` from an ad-hoc REPL or scratch script | `requirements.txt` | Has to be importable by one specific interpreter. |
| A library a project needs | That project's own venv (`uv add` / `uv sync`) | Pinned and versioned with the project, not with your laptop. |
| A one-off script's dependency | `uv run --with httpx script.py`, or PEP 723 inline metadata | No global install at all. |

Roughly half of the old `requirements.txt` was in the wrong row: they were
command-line applications, which is why they have moved to `python-tools.sh`.

## 3. Findings by package

### Abandoned or superseded by the standard library

| Package | Verdict |
| --- | --- |
| `pep8` | Renamed to `pycodestyle` in 2016; the PyPI package is a dead stub. Remove. |
| `pydocstyle` | Archived upstream. Its checks are ruff's `D` rules. |
| `pytz` | Superseded by stdlib `zoneinfo` (3.9+). Nothing new should use it. |
| `nodeenv` | Puts Node inside a Python venv. nvm already manages Node. |
| `pip-review` | An upgrade helper; `uv` and `update.sh` do this now. |

### Superseded by ruff, which you already have as a uv tool

`autopep8` (→ `ruff format`), `isort` (→ ruff rule set `I`), `pycodestyle`,
`pyflakes`, and `pylama` (a wrapper around the others) are all covered by ruff.

**The highest-leverage cleanup in this repo**: `.vimrc` pins ALE to flake8 and
pylint —

```vim
let g:ale_python_flake8_options='--ignore=E501,E231'
let g:ale_python_pylint_options='--disable=C0301 --extension-pkg-whitelist=pydantic'
```

so both must exist as commands (they are now uv tools for that reason). Switch
ALE to ruff and eight packages collapse into one:

```vim
let g:ale_linters = {'python': ['ruff']}
let g:ale_fixers  = {'python': ['ruff', 'ruff_format']}
```

Then `flake8`, `pylint`, `autopep8`, `isort`, `pycodestyle`, `pyflakes`,
`pydocstyle` and `pylama` can all go.

### Useful, but only inside a project's own environment

`pytest`, `ipdb` and `types-requests` cannot see a project's code or
dependencies when installed globally. A global `pytest` run against a project
venv is a well-known source of confusing `ImportError`s. These are better added
per project. They are cheap to keep, so they are still listed — just be aware
that the copy that matters is the one in the project venv.

### Build risk — the most likely cause of a failed fresh install

`mysqlclient` publishes **Windows-only wheels**. On macOS it compiles against
libmysqlclient and needs `mysql_config` at build time. It works on this machine
only because `mysql-client@8.0` happens to be installed — and that formula is
*not in the Brewfile*. On a clean machine the `mysql` formula does provide
`mysql_config`, so it should build, but this is the fragile entry.

If you do not specifically need the C driver, `pymysql` is pure Python and
installs everywhere with no toolchain. For interactive use, `mycli` (already in
the Brewfile) covers it.

### Marginal value

| Package | Note |
| --- | --- |
| `pastel` | Terminal colour library; almost certainly arrived as a transitive dependency of poetry rather than a deliberate choice. |
| `prettyconf` | Niche config loader. `os.environ` or `pydantic-settings` covers this, and you already have pydantic. |
| `github3.py` | Last meaningful release was 4.0.1 (2022). The `gh` CLI in your Brewfile covers most of it; `PyGithub` is the better-maintained library. |
| `pyopenssl` | A legacy shim over `cryptography` (which is installed anyway as a dependency). Only needed by old code that imports `OpenSSL` directly. |
| `isodate` | `datetime.fromisoformat` handles most ISO 8601 as of 3.11. Keep only if you parse ISO **durations**. |
| `sslyze` | A CLI, not a library, and your Brewfile already has `sslscan`. |
| `websocket-client` + `websockets` | Two different libraries (sync vs async). Fine to keep both if you use both; otherwise `websockets` is the modern one. |

### Clearly worth keeping as a global scratch set

`requests`, `beautifulsoup4`, `lxml`, `numpy`, `openpyxl`, `xlsxwriter`,
`pyyaml`, `xmltodict`, `python-dateutil`, `pymongo`, `pydantic`, `pyjwt`,
`ipython`.

`ipython` is deliberately **not** a uv tool: as an isolated tool it could not
import any of the libraries above, which defeats the purpose of a scratch REPL.

## 4. `pynvim` deserves its own environment

`pynvim` only works if it is importable by the interpreter neovim uses. It
currently lands in `pyenv global`, so the next time `install.sh` bumps the
pinned Python, neovim's Python provider breaks until the requirements are
reinstalled. A dedicated venv makes it version-independent:

```bash
uv venv ~/.venvs/neovim
uv pip install --python ~/.venvs/neovim/bin/python pynvim
```

```vim
let g:python3_host_prog = expand('~/.venvs/neovim/bin/python')
```

## 5. Suggested end state for `requirements.txt`

If you adopt the ALE-to-ruff change and drop the per-project and marginal
entries, the whole file becomes:

```
# HTTP and scraping
requests
beautifulsoup4
lxml
websockets

# Data and file formats
numpy
openpyxl
xlsxwriter
pyyaml
xmltodict
python-dateutil

# Databases
pymongo
pymysql          # replaces mysqlclient; no C toolchain needed

# Validation and auth
pydantic
pyjwt

# Scratch REPL
ipython
```

Everything commented out in the current `requirements.txt` is recorded there
with its reason, so nothing is lost by deleting it later. Note that commenting
a package out does **not** uninstall it — to clear the old set out of the new
interpreter:

```bash
uv pip list  --python "$(pyenv prefix 3.14.7)/bin/python"
uv pip uninstall --python "$(pyenv prefix 3.14.7)/bin/python" <package>...
```

## 6. Two further ideas

**Lock the library set.** For a genuinely reproducible record, compile a
lockfile and install from that instead:

```bash
uv pip compile requirements.txt -o requirements.lock   # commit this
uv pip sync requirements.lock --python "$(pyenv prefix 3.14.7)/bin/python"
```

`uv pip sync` also *removes* anything not in the lockfile, which makes the
interpreter exactly match the record rather than merely containing it. The
current set resolves to 63 packages on 3.14 — that resolution has been checked.

**uv can replace pyenv.** `uv python install 3.14` manages CPython builds
directly and is much faster than pyenv's source builds. Your Brewfile also
carries `asdf` alongside `pyenv` and nvm — three version managers, of which
asdf appears unused. Consolidating to `uv` (Python) + nvm (Node) would remove
two of them. This has deliberately not been changed, since `pyenv` was an
explicit requirement.
