#!/usr/bin/env bash
# Tests scripts/show-claude-error.sh with sample execution files.
set -euo pipefail
cd "$(dirname "$0")/../.."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
run() { bash scripts/show-claude-error.sh "$1" 2>&1; }
has()  { if grep -qF -- "$3" <<<"$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ $1: expected '$3' in:"; while IFS= read -r l; do echo "       $l"; done <<<"$2"; fi; }
lacks(){ if grep -qF -- "$3" <<<"$2"; then fail=$((fail+1)); echo "   ✗ $1: did not expect '$3'"; else pass=$((pass+1)); fi; }

# 1. JSON array, auth error in the result
cat >"$tmp/auth.json" <<'J'
[{"type":"system","subtype":"init"},
 {"type":"assistant","message":{"content":[{"type":"text","text":"Invalid API key · Please run /login"}]},"error":"authentication_failed"},
 {"type":"result","subtype":"success","is_error":true,"result":"Invalid API key · Please run /login"}]
J
out="$(run "$tmp/auth.json")"
has   "auth: shows the error"          "$out" "::error title=Claude failed::Invalid API key · Please run /login"
has   "auth: shows the error code"     "$out" "::error title=Claude failed::authentication_failed"
has   "auth: credential hint"          "$out" "credential was rejected"
if [[ "$(grep -c 'Invalid API key' <<<"$out")" -eq 1 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ auth: duplicate lines not removed"; fi

# 2. One message per line, usage limit
cat >"$tmp/limit.jsonl" <<'J'
{"type":"system","subtype":"init"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Claude AI usage limit reached|1760000000"}]}}
{"type":"result","subtype":"success","is_error":true,"result":"Claude AI usage limit reached|1760000000"}
J
out="$(run "$tmp/limit.jsonl")"
has   "limit: shows the error"         "$out" "usage limit reached"
has   "limit: usage hint"              "$out" "usage limit was hit"

# 3. Successful run: print nothing, never leak review text
cat >"$tmp/ok.json" <<'J'
[{"type":"assistant","message":{"content":[{"type":"text","text":"PRIVATE REVIEW TEXT"}]}},
 {"type":"result","subtype":"success","is_error":false,"result":"PRIVATE REVIEW TEXT"}]
J
out="$(run "$tmp/ok.json")"
lacks "success: no review text"        "$out" "PRIVATE REVIEW TEXT"
lacks "success: no error annotation"   "$out" "::error"

# 4. Only the LAST assistant reply of a failed run is shown
cat >"$tmp/long.json" <<'J'
[{"type":"assistant","message":{"content":[{"type":"text","text":"EARLIER REVIEW TEXT"}]}},
 {"type":"assistant","message":{"content":[{"type":"text","text":"Reached max turns"}]}},
 {"type":"result","subtype":"error_max_turns","is_error":true}]
J
out="$(run "$tmp/long.json")"
has   "long: subtype shown"            "$out" "::error title=Claude failed::subtype: error_max_turns"
lacks "long: last reply hidden"        "$out" "Reached max turns"
lacks "long: earlier reply hidden"     "$out" "EARLIER REVIEW TEXT"
lacks "long: no misleading hint"       "$out" "Likely fix"

# 5. Missing and broken files never fail the step
out="$(run "$tmp/missing.json")"; has "missing: explains" "$out" "No execution file"
echo 'not json' >"$tmp/broken.json"
if out="$(run "$tmp/broken.json")"; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ broken: exited non-zero"; fi
lacks "broken: prints nothing"         "$out" "::error"

# 6. Successful run with a denied tool: warn with the tool and command, no review text
cat >"$tmp/denied.json" <<'J'
[{"type":"assistant","message":{"content":[{"type":"text","text":"PRIVATE REVIEW TEXT"}]}},
 {"type":"result","subtype":"success","is_error":false,"result":"PRIVATE REVIEW TEXT",
  "permission_denials":[{"tool_name":"Bash","tool_use_id":"t1","tool_input":{"command":"gh pr comment 8 --body-file /tmp/review.md"}},
                        {"tool_name":"Read","tool_use_id":"t2","tool_input":{"file_path":"/etc/hosts"}}]}]
J
out="$(run "$tmp/denied.json")"
has   "denied: bash command shown"     "$out" "::warning title=Claude was denied a tool::Bash: gh pr comment 8 --body-file /tmp/review.md"
has   "denied: file tool shown"        "$out" "Read: /etc/hosts"
lacks "denied: no review text"         "$out" "PRIVATE REVIEW TEXT"
lacks "denied: not reported as error"  "$out" "::error"

# 7. CR/LF in Claude-controlled text cannot start a new workflow command; % is escaped
printf '%s\n' '[{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom\r::stop-commands::x\n::notice::fake 100%"}]' >"$tmp/inject.json"
out="$(run "$tmp/inject.json")"
if grep -qE '(^|\r)::(stop-commands|notice)::' <<<"$out"; then fail=$((fail+1)); echo "   ✗ inject: a new workflow command was started"; else pass=$((pass+1)); fi
has   "inject: flattened into one line" "$out" "boom ::stop-commands::x ::notice::fake 100%25"

# 8. errors[] array, null tool_input, credit hint
cat >"$tmp/credit.json" <<'J'
[{"type":"result","subtype":"error_during_execution","is_error":true,
  "errors":["Your credit balance is too low to access the Anthropic API."],
  "permission_denials":[{"tool_name":"Bash","tool_use_id":"t1","tool_input":null}]}]
J
out="$(run "$tmp/credit.json")"
has   "credit: errors[] shown"         "$out" "credit balance is too low"
has   "credit: credit hint"            "$out" "out of credit"
has   "credit: null input handled"     "$out" "denied a tool::Bash: (input hidden)"

# 9. Words like "token" or "login" in an unrelated error give no credential hint
printf '%s\n' '[{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Prompt is too long: 250000 tokens > 200000 maximum; see the login docs"}]' >"$tmp/toolong.json"
out="$(run "$tmp/toolong.json")"
has   "toolong: error shown"           "$out" "Prompt is too long"
lacks "toolong: no credential hint"    "$out" "credential was rejected"

# 10. Denied commands are cut at the first quote, heredoc or $( so their payload stays out of logs
cat >"$tmp/payload.json" <<'J'
[{"type":"result","subtype":"success","is_error":false,"permission_denials":[
  {"tool_name":"Bash","tool_input":{"command":"gh pr comment 7 --body '## AI Review SECRET-A'"}},
  {"tool_name":"Bash","tool_input":{"command":"cat > /tmp/r.md <<'EOF' SECRET-B"}},
  {"tool_name":"Bash","tool_input":{"command":"echo $(cat SECRET-C)"}},
  {"tool_name":"Grep","tool_input":{"pattern":"needle"}}]}]
J
out="$(run "$tmp/payload.json")"
has   "payload: command kept"          "$out" "Bash: gh pr comment 7 --body"
has   "payload: heredoc cut"           "$out" "Bash: cat > /tmp/r.md"
has   "payload: substitution cut"      "$out" "Bash: echo"
has   "payload: non-Bash tool kept"    "$out" "Grep: needle"
lacks "payload: quoted body hidden"    "$out" "SECRET-A"
lacks "payload: heredoc body hidden"   "$out" "SECRET-B"
lacks "payload: substitution hidden"   "$out" "SECRET-C"

echo "   show-claude-error: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
