#!/usr/bin/env bash
# PreToolUse guard — second safety net behind settings.json "deny".
# Reads the tool call JSON on stdin. Exit code 2 = block and tell Claude why.
set -euo pipefail

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

block() { echo "BLOCKED by .claude/hooks/guard.sh: $1" >&2; exit 2; }

if [[ "$tool" == "Bash" ]]; then
  # Never touch protected branches or history
  [[ "$cmd" =~ git[[:space:]]+push.*(main|master|production)([[:space:]]|$) ]] && block "push to protected branch"
  [[ "$cmd" =~ git[[:space:]]+push.*(--force|-f([[:space:]]|$)) ]] && block "force push"
  [[ "$cmd" =~ git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin ]] && block "hard reset to remote"
  # No merging / releasing — humans do that
  [[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+merge ]] && block "merging is a human gate"
  [[ "$cmd" =~ gh[[:space:]]+release ]] && block "releasing is a human gate"
  # No secrets in output
  [[ "$cmd" =~ (cat|less|head|tail|grep|printenv|env)([[:space:]].*)?\.env ]] && block "reading .env files"
  [[ "$cmd" =~ ^[[:space:]]*(printenv|env)[[:space:]]*$ ]] && block "dumping environment variables"
  # No remote DB / prod commands
  [[ "$cmd" =~ (psql|pg_dump|medusa[[:space:]]+db:migrate).*(prod|staging) ]] && block "DB command against staging/prod"
fi

if [[ "$tool" == "Edit" || "$tool" == "Write" ]]; then
  [[ "$path" =~ (^|/)\.env ]] && block "editing .env files"
  [[ "$path" =~ \.(pem|key|p12)$ ]] && block "editing key material"
fi

exit 0
