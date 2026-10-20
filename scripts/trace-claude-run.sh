#!/usr/bin/env bash
# TEMPORARY debug helper — prints the tool calls Claude made (name + short input)
# and its final reply. Never prints tool results. Remove after diagnosis.
set -euo pipefail
f="${1:?execution file}"
[[ -s "$f" ]] || { echo "no execution file"; exit 0; }
jq -rs '
  [ .[] | if type == "array" then .[] else . end ] as $m
  | ($m[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
     | "TOOL \(.name): \((.input.command // .input.file_path // .input.pattern // .input.prompt // .input.description // (.input|tostring)) | tostring | gsub("\\s+"; " ") | .[0:200])"),
    "FINAL: \(([$m[] | select(.type == "result")] | last | .result // "") | tostring | .[0:1500])"
' "$f" || true
