#!/usr/bin/env bash
# Usage: scripts/show-claude-error.sh <claude-execution-output.json>
#
# claude-code-action hides Claude's output in logs (it may contain repo content),
# so a failed run only says "is_error: true". This prints:
#   - tool calls that were denied permission (any run): tool name + a short input,
#     because a denied tool can make a "successful" run silently do nothing
#   - for a run that ended in an error: the result message and Claude's last reply,
#     plus a hint for common causes
# A clean successful run prints nothing, so review text never reaches the logs.
set -euo pipefail
file="${1:?usage: show-claude-error.sh <execution-file>}"

if [[ ! -s "$file" ]]; then
  echo "::error title=Claude failed::No execution file at $file. Claude failed before it started; see the claude-code-action step log above."
  exit 0
fi

# Accepts a JSON array of messages or one JSON message per line.
denied="$(jq -rs '
  [ .[] | if type == "array" then .[] else . end ]
  | .[] | select(.type == "result") | .permission_denials[]?
  | "\(.tool_name): \((.tool_input.command // .tool_input.file_path // .tool_input.pattern // (.tool_input | tostring))
      | tostring | gsub("\\s+"; " ") | .[0:160])"
' "$file" 2>/dev/null | awk '!seen[$0]++' || true)"
while IFS= read -r line; do
  [[ -n "$line" ]] && echo "::warning title=Claude was denied a tool::$line — allow it in the workflow's --allowedTools if Claude needs it."
done <<<"$denied"

msg="$(jq -rs '
  [ .[] | if type == "array" then .[] else . end ] as $m
  | [ $m[] | select(.type == "result" and .is_error == true) ] as $errs
  | if ($errs | length) == 0 then empty else
      ( [ $m[] | select(.type == "assistant") ] | last
        | [ (.error // empty), (.message.content[]? | select(.type == "text") | .text) ] ),
      ( $errs | map((.result // empty), (.errors[]? // empty)) )
      | .[]
    end
  | select(type == "string" and . != "")
' "$file" 2>/dev/null | awk '!seen[$0]++' || true)"

[[ -n "$msg" ]] || exit 0

while IFS= read -r line; do
  [[ -n "$line" ]] && echo "::error title=Claude failed::$line"
done <<<"$msg"

lower="$(tr '[:upper:]' '[:lower:]' <<<"$msg")"
hint=""
case "$lower" in
  *"credit balance"*)                         hint="The Console account behind ANTHROPIC_API_KEY is out of credit." ;;
  *"usage limit"*|*"rate limit"*|*"quota"*)   hint="The subscription or API usage limit was hit. Wait for it to reset, or switch credential." ;;
  *"api key"*|*"oauth"*|*"token"*|*"login"*|*"authentication"*|*"unauthorized"*|*"401"*|*"403"*)
    hint="The Claude credential was rejected. Recreate it (claude setup-token or a new Console key) and update the GitHub secret. Set only one of ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN." ;;
esac
[[ -z "$hint" ]] || echo "::notice title=Likely fix::$hint"
