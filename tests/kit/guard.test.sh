#!/usr/bin/env bash
# Tests .claude/hooks/guard.sh: each case is "expected|tool|command-or-path".
# Add a case here whenever you change the hook — both the thing it must block
# and a nearby thing it must still allow.
set -euo pipefail
cd "$(dirname "$0")/../.."

pass=0; fail=0
while IFS='|' read -r expect tool arg; do
  [[ -z "$expect" || "$expect" == \#* ]] && continue
  if [[ "$tool" == "Bash" ]]; then
    json=$(jq -cn --arg c "$arg" '{tool_name:"Bash",tool_input:{command:$c}}')
  else
    json=$(jq -cn --arg t "$tool" --arg p "$arg" '{tool_name:$t,tool_input:{file_path:$p}}')
  fi
  if printf '%s' "$json" | bash .claude/hooks/guard.sh >/dev/null 2>&1; then got=allow; else got=block; fi
  if [[ "$got" == "$expect" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ expected $expect, got $got: [$tool] $arg"; fi
done <<'EOF'
# --- protected branches / history
block|Bash|git push origin main
block|Bash|git push -u origin main
block|Bash|git push origin HEAD:main
block|Bash|git push origin refs/heads/master
block|Bash|git push --force origin ai/1-x
block|Bash|git push origin ai/1-x -f
allow|Bash|git push origin ai/42-domain
allow|Bash|git push -u origin ai/7-main-nav
allow|Bash|git push origin ai/9-fix
block|Bash|git reset --hard origin/main
# --- merging / releasing
block|Bash|gh pr merge 12
allow|Bash|gh pr view 12
block|Bash|gh release create v1.0.0
block|Bash|gh release edit v1.0.0 --draft=false
block|Bash|gh release delete v1.0.0 -y
block|Bash|gh release upload v1.0.0 build.zip
block|Bash|gh release delete-asset v1.0.0 x.zip
block|Bash|gh release
block|Bash|gh release view v1 && gh release create v2
block|Bash|gh release list; gh release delete v1
allow|Bash|gh release download v1.7.12 -R rhysd/actionlint -p x.tar.gz
allow|Bash|gh release list -R cli/cli
allow|Bash|gh release view v1.0.0
allow|Bash|gh release verify v1.0.0
allow|Bash|gh release verify-asset v1.0.0 x.tgz
# --- secrets in shell commands
block|Bash|cat .env
block|Bash|cat apps/backend/.env.production
block|Bash|grep KEY "apps/backend/.env"
block|Bash|head -n 5 ./.env.local
allow|Bash|cat .env.example
allow|Bash|cat apps/backend/.env.template
allow|Bash|grep -rn "\.env" docs/
allow|Bash|cat > .gitignore <<'X'
allow|Bash|cat .environment.md
# words inside messages count too (documented in guard.sh and docs/ai-workflow.md)
block|Bash|git commit -m "stop tracking .env"
allow|Bash|git commit -m "add .env.example for new devs"
allow|Bash|git commit -F /tmp/msg.txt
block|Bash|env
block|Bash|printenv
block|Bash|printenv DATABASE_URL
block|Bash|env | grep TOKEN
allow|Bash|env NODE_ENV=test pnpm test
allow|Bash|pnpm env use 20
# --- remote DB
block|Bash|psql $PROD_URL -c "select 1" --host prod
block|Bash|pnpm medusa db:migrate --env staging
allow|Bash|pnpm medusa db:migrate
# --- file tools
block|Edit|.env
block|Write|apps/backend/.env.local
block|MultiEdit|.env
block|NotebookEdit|./.env.staging
allow|Edit|.env.example
allow|Write|apps/backend/.env.template
block|Write|certs/server.key
allow|Write|src/env.ts
block|Read|.env
block|Read|apps/backend/.env.production
block|Read|/abs/path/.env.custom
allow|Read|.env.example
allow|Read|apps/backend/.env.template
allow|Read|src/env.ts
allow|Read|README-AI-SETUP.md
EOF

echo "   guard: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
