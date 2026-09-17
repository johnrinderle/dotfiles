# Check GCP auth on interactive shell startup and offer to re-auth if stale.
#
# Tracked in the dotfiles repo. install.sh symlinks this to
# ~/gcloud-auth-check.sh and .zshrc sources it from there -- no manual install.
#
# Config:
#   GCLOUD_AUTH_CHECK=0          # hard off switch
#   GCLOUD_AUTH_MODE=prompt      # prompt (default) | notify | auto
#                                #   prompt = ask, default YES
#                                #   notify = print a warning, never launch a browser
#                                #   auto   = run login without asking
#   GCLOUD_AUTH_THROTTLE=1800    # seconds between checks; 0 = every shell
#
# Manual re-auth at any time:  gauth

_gcloud_auth_is_agent_shell() {
  # Any one of these means an AI agent spawned this shell. OR-chained, so
  # extra signals are strictly protective -- a false positive just means a
  # skipped prompt, a false negative means a browser stealing your focus.
  # Verified against a real Claude desktop / Claude Code 2.1.260 environment.

  [ -n "$AI_AGENT" ]                  && return 0  # e.g. claude-code_2-1-260_agent
  [ -n "$CLAUDECODE" ]                && return 0  # =1, documented
  [ -n "$CLAUDE_CODE_CHILD_SESSION" ] && return 0  # =1, documented
  [ -n "$CLAUDE_AGENT_SDK_VERSION" ]  && return 0  # e.g. 0.3.260
  [ -n "$CLAUDE_CODE_SESSION_ID" ]    && return 0
  [ -n "$CLAUDE_CODE_ENTRYPOINT" ]    && return 0  # e.g. claude-desktop
                                                   # (docs say this is scrubbed
                                                   #  in some headless paths --
                                                   #  a bonus, not a keystone)

  # macOS: the Claude desktop app identifies itself at the bundle level,
  # independent of any CLAUDE_* naming convention.
  case "${__CFBundleIdentifier:-}" in
    com.anthropic.*) return 0 ;;
  esac

  return 1
}

_gcloud_auth_is_human_tty() {
  # Every condition must hold before we are willing to steal focus with a
  # browser window. These are machine-checkable facts, not requests.

  [ "${GCLOUD_AUTH_CHECK:-1}" != "0" ] || return 1

  # 1. Interactive shell (not a script or subshell).
  case "$-" in
    *i*) ;;
    *) return 1 ;;
  esac

  # 2. stdin AND stdout are real terminals. Claude Code's Bash tool runs
  #    non-interactive shells with no pty, so both are false there.
  [ -t 0 ] && [ -t 1 ] || return 1

  # 3. Not a dumb/absent terminal (Emacs shell-mode, various harnesses).
  case "${TERM:-}" in
    ""|dumb) return 1 ;;
  esac

  # 4. Not an agent-spawned shell.
  ! _gcloud_auth_is_agent_shell || return 1

  return 0
}

_gcloud_auth_check() {
  _gcloud_auth_is_human_tty || return 0
  command -v gcloud >/dev/null 2>&1 || return 0

  local mode="${GCLOUD_AUTH_MODE:-prompt}"
  local throttle="${GCLOUD_AUTH_THROTTLE:-1800}"
  local stamp="${TMPDIR:-/tmp}/.gcloud-auth-check.$(id -u)"

  # Throttle: skip if checked recently (no network call per new tab).
  if [ "$throttle" -gt 0 ] && [ -f "$stamp" ]; then
    local now last
    now=$(date +%s)
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    [ $((now - last)) -lt "$throttle" ] && return 0
  fi

  # Refreshes the active credential; non-zero means the session is dead.
  if gcloud auth print-access-token >/dev/null 2>&1; then
    date +%s > "$stamp" 2>/dev/null
    return 0
  fi

  echo "gcloud: not authenticated (or session expired)." >&2

  if [ "$mode" = "notify" ]; then
    echo "Run 'gauth' to re-authenticate." >&2
    return 0
  fi

  if [ "$mode" = "auto" ]; then
    gcloud auth login && date +%s > "$stamp" 2>/dev/null
    return 0
  fi

  # Prompt, default YES: bare Enter proceeds, only an explicit n/no declines.
  # The `|| reply=n` catches read FAILING (EOF / closed stdin) -- that is not
  # someone accepting the default, it is nobody being there to answer.
  local reply=""
  printf 'Run `gcloud auth login` now? [Y/n] ' >&2
  read -r reply || reply=n
  case "$reply" in
    [Nn]|[Nn][Oo]) echo "Skipped. Run 'gauth' when ready." >&2 ;;
    *) gcloud auth login && date +%s > "$stamp" 2>/dev/null ;;
  esac
}

# Deliberate, human-invoked re-auth. Bypasses all guards by design.
gauth() {
  gcloud auth login && date +%s > "${TMPDIR:-/tmp}/.gcloud-auth-check.$(id -u)" 2>/dev/null
}

_gcloud_auth_check

# ---------------------------------------------------------------------------
# Why this fires "when you open Claude":
#
# Claude Code sources ~/.zshrc at SESSION START to capture your aliases,
# functions, and shell options -- so an rc-file hook runs once per Claude
# session. Individual Bash tool commands run in non-interactive, non-login
# shells (zsh sources only ~/.zshenv for those).
#
# To re-verify the marker list after a Claude Code upgrade:
#   normal terminal:   env | sort > /tmp/env.human
#   from Claude:       env | sort > /tmp/env.agent
#   diff /tmp/env.human /tmp/env.agent && rm -f /tmp/env.human /tmp/env.agent
# ---------------------------------------------------------------------------
