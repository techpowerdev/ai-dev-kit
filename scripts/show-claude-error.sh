#!/usr/bin/env bash
# Usage: show-claude-error.sh <claude-execution-output.json>
#
# claude-code-action hides Claude's output in logs (it may contain repo content),
# so a failed run only says "is_error: true". This prints, as GitHub annotations:
#   - tool calls that were denied permission (any run): tool name + a short input,
#     because a denied tool can make a "successful" run silently do nothing
#   - for a run that ended in an error: the result subtype, error codes and the
#     result message (max 300 chars), plus a hint for well-known causes
# It never prints Claude's replies, so review text or data Claude read (e.g. from
# monitoring) does not reach public logs. A clean successful run prints nothing.
#
# Workflows run a copy taken before Claude starts (see "Snapshot CI helpers"),
# so Claude cannot change what this script does.
set -euo pipefail
file="${1:?usage: show-claude-error.sh <execution-file>}"

# Annotations end at a newline and treat a bare CR as one, so text from Claude
# could otherwise start a new ::command::. Flatten whitespace and escape %.
annotate() {  # annotate <level> <title> <message>
  local msg="${3//%/%25}"
  msg="${msg//$'\r'/ }"; msg="${msg//$'\n'/ }"
  echo "::$1 title=$2::$msg"
}

if [[ ! -s "$file" ]]; then
  annotate error "Claude failed" "No execution file at $file. Claude failed before it started; see the claude-code-action step log above."
  exit 0
fi

# Accepts a JSON array of messages or one JSON message per line.
messages='[ .[] | if type == "array" then .[] else . end ]'
flat='tostring | gsub("[\\s]+"; " ")'

denied="$(jq -rs "$messages"' | .[] | select(.type == "result") | .permission_denials[]?
  | "\(.tool_name // "unknown tool"): \((.tool_input // {}) as $i
      | ($i.command // $i.file_path // $i.pattern // $i.url // ($i | tostring)) | '"$flat"' | .[0:160])"
' "$file" 2>/dev/null | awk '!seen[$0]++' || true)"
while IFS= read -r line; do
  [[ -n "$line" ]] && annotate warning "Claude was denied a tool" "$line — allow it in the workflow's --allowedTools if Claude needs it."
done <<<"$denied"

errors="$(jq -rs "$messages"' as $m
  | [ $m[] | select(.type == "result" and .is_error == true) ] as $errs
  | if ($errs | length) == 0 then empty else
      ( $errs[] | select(.subtype != null and .subtype != "success") | "subtype: \(.subtype)" ),
      ( $m[] | select(.type == "assistant") | .error // empty ),
      ( $errs[] | (.errors[]? // empty), (.result // empty) )
    end
  | select(type == "string" and . != "") | '"$flat"' | .[0:300]
' "$file" 2>/dev/null | awk '!seen[$0]++' || true)"

[[ -n "$errors" ]] || exit 0

while IFS= read -r line; do
  [[ -n "$line" ]] && annotate error "Claude failed" "$line"
done <<<"$errors"

# Hints only for exact, well-known error shapes; ordinary words like "token" do not count.
lower="$(tr '[:upper:]' '[:lower:]' <<<"$errors")"
hint=""
if grep -qE 'credit balance is too low|billing_error' <<<"$lower"; then
  hint="The Console account behind ANTHROPIC_API_KEY is out of credit."
elif grep -qE 'usage limit reached|rate_limit|api error: 429' <<<"$lower"; then
  hint="The subscription or API usage limit was hit. Wait for it to reset, or switch credential."
elif grep -qE 'authentication_failed|api error: 40[13]|invalid api key|oauth (access )?token (is invalid|has expired|has been revoked)' <<<"$lower"; then
  hint="The Claude credential was rejected. Recreate it (claude setup-token, /install-github-app or a new Console key) and update the GitHub secret. Set only one of ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN."
fi
[[ -z "$hint" ]] || annotate notice "Likely fix" "$hint"
