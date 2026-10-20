#!/usr/bin/env bash
# PreToolUse guard — second safety net behind settings.json "deny".
# Reads the tool call JSON on stdin. Exit code 2 = block and tell Claude why.
set -euo pipefail
set -f   # never glob-expand: the hook inspects text, it must not match files on disk
# Fail closed: an unexpected error (e.g. jq missing) blocks the tool call instead of
# letting it through. Exit 2 is "block" for Claude Code; exit 1 would mean "allow".
trap 'echo "BLOCKED by .claude/hooks/guard.sh: hook error on line $LINENO; fix the hook or run the command yourself" >&2; exit 2' ERR
command -v jq >/dev/null || { echo "BLOCKED by .claude/hooks/guard.sh: jq is required" >&2; exit 2; }

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty')"
pattern="$(printf '%s' "$input" | jq -r '.tool_input.glob // (if .tool_name == "Glob" then .tool_input.pattern else empty end) // empty')"

block() { echo "BLOCKED by .claude/hooks/guard.sh: $1" >&2; exit 2; }

# A "secret env file" is .env or .env.<anything>, except the documented examples.
# Matched as a whole path segment so ".environment" or "docs/env.md" do not trigger it.
is_secret_env_path() {
  local p="$1"
  [[ "$p" =~ (^|/)\.env(\.[A-Za-z0-9_.-]+)?$ ]] || return 1
  [[ "$p" =~ \.env\.(example|template|sample)$ ]] && return 1
  return 0
}

# Files that hold credentials even though they are not env files: the git config
# (actions/checkout and claude-code-action store a token there) and process
# environments under /proc.
is_credential_path() {
  [[ "$1" =~ (^|/)\.git/config$ || "$1" =~ ^/proc/[^/]+/environ$ ]]
}

# Expands one level of {a,b} braces per call, up to 3 levels and 64 variants.
# Pure string work: nothing is evaluated.
brace_variants() {
  local w="$1" depth="${2:-0}" pre body post alt
  if (( depth < 3 )) && [[ "$w" =~ ^([^{]*)\{([^{}]*)\}(.*)$ ]]; then
    pre="${BASH_REMATCH[1]}"; body="${BASH_REMATCH[2]}"; post="${BASH_REMATCH[3]}"
    local IFS=','
    for alt in $body; do brace_variants "$pre$alt$post" $((depth + 1)); done | head -64
  else
    printf '%s\n' "$w"
  fi
}

# True if a word, after brace expansion, names a secret or credential file, or is a
# glob whose last part could expand to one (.en*, .en[v], .e?v). Bash globs only
# match a dotfile when the pattern starts with a literal ".", so "*" or "[.]env"
# alone do not count.
names_secret() {
  local v base name
  while IFS= read -r v; do
    is_secret_env_path "$v" && return 0
    is_credential_path "$v" && return 0
    base="${v##*/}"
    if [[ "$base" == .* && "$base" == *[*?[]* ]]; then
      for name in .env .env.local .env.development .env.test .env.staging .env.production; do
        # shellcheck disable=SC2053  # $base is intentionally a glob pattern
        [[ "$name" == $base ]] && return 0
      done
    fi
  done < <(brace_variants "$1")
  return 1
}

if [[ "$tool" == "Bash" ]]; then
  # --- Protected branches / history -------------------------------------
  # Only look at the refspec argument of `git push`, not every word in the command,
  # so "ai/42-domain" or "ai/7-main-nav" are not mistaken for "main".
  if [[ "$cmd" =~ git[[:space:]]+push ]]; then
    # Strip options like -u / --set-upstream, then take "<remote> <refspec>"
    push_args="$(printf '%s' "$cmd" | sed -E 's/.*git[[:space:]]+push//; s/[[:space:]]+-(u|-set-upstream|-tags|-follow-tags)([[:space:]]|$)/ /g')"
    refspec="$(printf '%s' "$push_args" | awk '{print $2}')"
    refspec="${refspec##*:}"           # "src:dst" -> "dst"
    refspec="${refspec#refs/heads/}"
    case "$refspec" in
      main|master|production) block "push to protected branch '$refspec'" ;;
      "") # no refspec given -> pushes the current branch
          current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
          case "$current" in main|master|production) block "push to protected branch '$current'" ;; esac ;;
    esac
    [[ "$cmd" =~ git[[:space:]]+push.*([[:space:]]--force|[[:space:]]-f)([[:space:]]|$) ]] && block "force push"
  fi
  [[ "$cmd" =~ git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin ]] && block "hard reset to remote"

  # --- No merging / releasing — humans do that ---------------------------
  [[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+merge ]] && block "merging is a human gate"
  # Read-only release subcommands are fine (e.g. downloading a tool's binary).
  # Everything else — create, edit, delete, upload, and any future subcommand — is blocked.
  # Checks every "gh release <sub>" in the command, so chaining with && cannot sneak one through.
  while read -r sub; do
    case "$sub" in
      list|view|download|verify|verify-asset) ;;
      *) block "releasing is a human gate (gh release ${sub:-<none>})" ;;
    esac
  done < <(printf '%s\n' "$cmd" | grep -oE 'gh[[:space:]]+release([[:space:]]+[^[:space:];&|]+)?' | awk '{print $3}')

  # --- No secrets in output ----------------------------------------------
  # Best effort and text only: the hook never runs the command, so some ways of
  # naming a file (a variable set elsewhere, a script, a generated name) are not seen.
  # Every word of the whole command is checked, including quoted strings, heredocs
  # and commit messages, so a message that names a secret env file is blocked too
  # (use `git commit -F <file>`). Words are formed like this:
  #   - backslash-newline continuations are joined; newlines and ; | & < > ( ) ` = :
  #     separate words; nothing is glob-expanded here
  #   - ANSI-C strings $'...' are decoded, then quotes and backslashes are removed,
  #     so a grep pattern "\.env" is blocked too (write it as "[.]env")
  #   - a glued short flag (-FPATH) is also checked without the flag
  #   - one trailing "." or "," is dropped
  # A word is blocked when names_secret matches it (see above).
  flat="${cmd//$'\\\n'/}"
  read -r -a words <<<"$(printf '%s' "$flat" | tr ';|&<>()`=:\n' '          ')"
  for tok in "${words[@]}"; do
    n=0
    while [[ "$tok" =~ \$\'([^\']*)\' ]] && (( n++ < 5 )); do
      decoded="$(printf '%b' "${BASH_REMATCH[1]}")"
      tok="${tok/"${BASH_REMATCH[0]}"/$decoded}"
    done
    tok="${tok//[\"\'\\]/}"
    tok="${tok%[.,]}"
    candidates=("$tok")
    [[ "$tok" =~ ^-[A-Za-z](.+)$ ]] && candidates+=("${BASH_REMATCH[1]}")   # -FPATH
    for c in "${candidates[@]}"; do
      if names_secret "$c"; then
        block "command references a secret or credential file ('$c')"
      fi
    done
  done
  [[ "$cmd" =~ (^|[[:space:];&|])(printenv|env)[[:space:]]*($|[;&|]) ]] && block "dumping environment variables"
  [[ "$cmd" =~ (^|[[:space:];&|])(printenv|env)[[:space:]]+[A-Z_]*(KEY|SECRET|TOKEN|PASSWORD|DATABASE_URL) ]] && block "printing a secret variable"

  # --- In CI, comments and PR/issue bodies come only from files in the repo ---
  # Prompt injection could ask Claude to post .git/config (which holds a token) or a
  # process environment as a comment. In GitHub Actions, for gh pr|issue:
  #   - no $(...)
  #   - --body-file / -F must be a plain relative path inside the checkout:
  #     letters, digits, _ . / - only (no $, ~, globs, braces), no ".." segment,
  #     nothing under .git/
  if [[ "${GITHUB_ACTIONS:-}" == "true" && "$flat" =~ gh[[:space:]]+(pr|issue)([[:space:]]|$) ]]; then
    [[ "$flat" == *"\$("* ]] && block "in CI, gh pr/issue commands may not use \$(...)"
    read -r -a gh_words <<<"$(printf '%s' "$flat" | tr ';|&<>()\n' '       ')"
    for ((i = 0; i < ${#gh_words[@]}; i++)); do
      w="${gh_words[i]//[\"\']/}"; f="__none__"
      case "$w" in
        --body-file=*) f="${w#--body-file=}" ;;
        --body-file|-F) f="${gh_words[i+1]:-}"; f="${f//[\"\']/}" ;;
        -F?*) f="${w#-F}" ;;
      esac
      [[ "$f" == "__none__" ]] && continue
      [[ "$f" =~ ^[A-Za-z0-9_.][A-Za-z0-9_./-]*$ ]] \
        || block "in CI, gh pr/issue may only post a plain relative file path (got '${f:-<none>}')"
      norm="/$f/"
      while [[ "$norm" == *"/./"* ]]; do norm="${norm//\/.\//\/}"; done
      while [[ "$norm" == *"//"* ]]; do norm="${norm//\/\//\/}"; done
      [[ "$norm" == *"/../"* || "$norm" == *"/.git/"* ]] \
        && block "in CI, gh pr/issue may only post a file inside the repo, outside .git/ (got '$f')"
    done
  fi

  # --- No remote DB / prod commands --------------------------------------
  [[ "$cmd" =~ (psql|pg_dump|medusa[[:space:]]+db:migrate).*(prod|staging) ]] && block "DB command against staging/prod"
fi

if [[ "$tool" == "Read" ]]; then
  is_secret_env_path "$path" && block "reading secret file '$path'"
  is_credential_path "$path" && block "reading a file that holds credentials ('$path')"
fi

# Grep and Glob can read or list the same files, so the same rules apply to their
# path and file pattern, and they may not search inside .git/.
if [[ "$tool" == "Grep" || "$tool" == "Glob" ]]; then
  for p in "$path" "$pattern"; do
    [[ -z "$p" ]] && continue
    if names_secret "$p"; then block "$tool on a secret or credential file ('$p')"; fi
    [[ "$p" =~ (^|/)\.git(/|$) ]] && block "$tool inside .git/ ('$p')"
  done
fi

if [[ "$tool" == "Edit" || "$tool" == "Write" || "$tool" == "MultiEdit" || "$tool" == "NotebookEdit" ]]; then
  is_secret_env_path "$path" && block "editing secret file '$path'"
  [[ "$path" =~ \.(pem|key|p12)$ ]] && block "editing key material"
fi

exit 0
