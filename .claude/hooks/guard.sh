#!/usr/bin/env bash
# PreToolUse guard — second safety net behind settings.json "deny".
# Reads the tool call JSON on stdin. Exit code 2 = block and tell Claude why.
set -euo pipefail

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"

block() { echo "BLOCKED by .claude/hooks/guard.sh: $1" >&2; exit 2; }

# A "secret env file" is .env or .env.<anything>, except the documented examples.
# Matched as a whole path segment so ".environment" or "docs/env.md" do not trigger it.
is_secret_env_path() {
  local p="$1"
  [[ "$p" =~ (^|/)\.env(\.[A-Za-z0-9_.-]+)?$ ]] || return 1
  [[ "$p" =~ \.env\.(example|template|sample)$ ]] && return 1
  return 0
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
  # Check every whitespace-separated word of the whole command, with quotes removed.
  # This includes words inside quoted strings, heredocs and commit messages, so a
  # message that names a secret env file is blocked too (write it to a file and use
  # `git commit -F`). A word only counts if it is exactly such a path: a regex like
  # "\.env" or a name like .env.example does not match.
  for tok in $cmd; do
    tok="${tok//[\"\']/}"
    if is_secret_env_path "$tok"; then
      block "command references secret file '$tok'"
    fi
  done
  [[ "$cmd" =~ (^|[[:space:];&|])(printenv|env)[[:space:]]*($|[;&|]) ]] && block "dumping environment variables"
  [[ "$cmd" =~ (^|[[:space:];&|])(printenv|env)[[:space:]]+[A-Z_]*(KEY|SECRET|TOKEN|PASSWORD|DATABASE_URL) ]] && block "printing a secret variable"

  # --- No remote DB / prod commands --------------------------------------
  [[ "$cmd" =~ (psql|pg_dump|medusa[[:space:]]+db:migrate).*(prod|staging) ]] && block "DB command against staging/prod"
fi

if [[ "$tool" == "Read" ]]; then
  is_secret_env_path "$path" && block "reading secret file '$path'"
fi

if [[ "$tool" == "Edit" || "$tool" == "Write" || "$tool" == "MultiEdit" || "$tool" == "NotebookEdit" ]]; then
  is_secret_env_path "$path" && block "editing secret file '$path'"
  [[ "$path" =~ \.(pem|key|p12)$ ]] && block "editing key material"
fi

exit 0
