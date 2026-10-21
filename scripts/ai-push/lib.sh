# shellcheck shell=bash
# Shared helpers for the trusted push flow (#12). Sourced by the other scripts in
# this folder; never executed on its own. Works with bash 3.2 (macOS) and 5.
#
# Nothing here reads input from the Claude job except as data: branch names, file
# lists and messages coming from an artifact are validated or sanitized first.

# A branch the AI may push: ai/<issue>-<slug>, lowercase slug, no "..", "//" or spaces.
AI_BRANCH_RE='^ai/[0-9]+-[a-z0-9]+(-[a-z0-9]+)*$'

# git with hooks, fsmonitor and other repo-controlled execution turned off, and object
# checks on for anything fetched from a bundle.
ai_git() {
  git -c core.hooksPath=/dev/null -c core.fsmonitor=false \
      -c fetch.fsckObjects=true -c transfer.fsckObjects=true -c receive.fsckObjects=true \
      "$@"
}

# ai_validate_branch <branch> [issue] — 0 if the AI may push to it.
ai_validate_branch() {
  local b="$1" n="${2:-}"
  [[ ${#b} -le 100 ]] || return 1
  [[ "$b" =~ $AI_BRANCH_RE ]] || return 1
  case "$b" in main|master|production) return 1 ;; esac
  if [[ -n "$n" ]]; then
    [[ "$n" =~ ^[0-9]+$ ]] || return 1
    [[ "$b" == "ai/$n-"* ]] || return 1
  fi
  return 0
}

# ai_sanitize <text> — one line, no control characters, no "::" so it cannot start a
# GitHub workflow command, "%" escaped. Use for anything that came from an artifact.
ai_sanitize() {
  local s
  s="$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' | tr '\r\n\t' '   ')"
  s="${s//%/%25}"
  while [[ "$s" == *"::"* ]]; do s="${s//::/: :}"; done
  printf '%s' "$s"
}

ai_note() { echo "::notice title=ai-push::$(ai_sanitize "$1")"; }
ai_warn() { echo "::warning title=ai-push::$(ai_sanitize "$1")"; }
ai_fail() { echo "::error title=ai-push::$(ai_sanitize "$1")"; exit 1; }

# ai_output <key> <value> — append to $GITHUB_OUTPUT when it is set.
ai_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; fi
}

# ai_high_risk_globs <labeler.yml> — the globs listed under "risk:high", one per line.
# Accepts "quoted", 'single-quoted' and bare list items; skips the "changed-files:" and
# "any-glob-to-any-file:" keys (they end with a colon). Fails (status 1, reason on
# stderr) on forms it cannot read safely, such as "- key: value" on one line or a
# [flow, list]: reading those wrongly would silently turn the high-risk check off.
ai_high_risk_globs() {
  local out
  out="$(awk '
    /^["\x27]?risk:high["\x27]?:/ { inblock = 1; next }
    /^[^[:space:]#]/ { inblock = 0 }
    inblock && /^[[:space:]]*-[[:space:]]*[^[:space:]]/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line); sub(/[[:space:]]+#.*$/, "", line); sub(/[[:space:]]+$/, "", line)
      if (line ~ /:$/) next
      if (line ~ /^[^"\x27]*:[[:space:]]/ || line ~ /[\[\]{}]/ && line !~ /^["\x27]/) { print "__UNREADABLE__ " line; next }
      if (line ~ /^".*"$/ || line ~ /^\x27.*\x27$/) line = substr(line, 2, length(line) - 2)
      if (line != "") print line
    }' "$1")" || return 1
  if grep -q '^__UNREADABLE__ ' <<<"$out"; then
    echo "Cannot read these risk:high entries safely: $(grep '^__UNREADABLE__ ' <<<"$out" | cut -c16- | tr '\n' ' ')" >&2
    return 1
  fi
  printf '%s\n' "$out" | grep -v '^$' || true
}

# ai_redact_userinfo <text> — hide "user:secret@" in any URL inside the text.
ai_redact_userinfo() {
  printf '%s' "$1" | sed -E 's#(://)[^/@[:space:]]+@#\1***@#g'
}

# ai_path_matches <path> <glob> — labeler-style match: "**" spans directories and a
# leading "**/" also matches at the repo root.
ai_path_matches() {
  local path="$1" glob="$2"
  # shellcheck disable=SC2053  # $glob is a pattern on purpose
  [[ "$path" == $glob ]] && return 0
  if [[ "$glob" == '**/'* ]]; then
    local rest="${glob#\*\*/}"
    # shellcheck disable=SC2053
    [[ "$path" == $rest ]] && return 0
  fi
  return 1
}
