#!/usr/bin/env bash
# Tests .claude/hooks/guard.sh: each case is "expected|tool|command-or-path".
# "block@ci" / "allow@ci" run the hook with GITHUB_ACTIONS=true; plain cases run
# without it, so results do not depend on where the tests run.
# "⏎" in a case stands for a newline, so multi-line commands can be tested.
# Add a case here whenever you change the hook — both the thing it must block
# and a nearby thing it must still allow.
set -euo pipefail
cd "$(dirname "$0")/../.."

pass=0; fail=0
while IFS='|' read -r expect tool arg; do
  [[ -z "$expect" || "$expect" == \#* ]] && continue
  arg="${arg//⏎/$'\n'}"
  if [[ "$tool" == "Bash" ]]; then
    json=$(jq -cn --arg c "$arg" '{tool_name:"Bash",tool_input:{command:$c}}')
  else
    json=$(jq -cn --arg t "$tool" --arg p "$arg" '{tool_name:$t,tool_input:{file_path:$p}}')
  fi
  ci=""; want="$expect"
  if [[ "$expect" == *@ci ]]; then ci=true; want="${expect%@ci}"; fi
  if printf '%s' "$json" | env -u GITHUB_ACTIONS ${ci:+GITHUB_ACTIONS=true} bash .claude/hooks/guard.sh >/dev/null 2>&1; then got=allow; else got=block; fi
  if [[ "$got" == "$want" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ expected $expect, got $got: [$tool] $arg"; fi
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
block|Bash|grep -rn "\.env" docs/
allow|Bash|grep -rn "[.]env" docs/
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
# --- secrets hidden by shell punctuation, flags or backslashes
block|Bash|cat<.env
block|Bash|cat <.env
block|Bash|true;cat .env
block|Bash|echo x|tee .env.local
block|Bash|cat .env>out.txt
block|Bash|echo $(cat .env)
block|Bash|echo `cat .env`
block|Bash|cat \.env
block|Bash|cat .e\nv
block|Bash|gh pr comment 1 --body-file=.env
block|Bash|gh pr comment 1 -F.env
block|Bash|git commit -m "stop tracking .env."
allow|Bash|git commit -m "add .env.example."
allow|Bash|cat docs/*.md
allow|Bash|echo "a;b" | grep a
# --- globs, braces, assignments, refs, ANSI-C quoting and credential files
block|Bash|cat .en*
block|Bash|cat apps/backend/.en*
block|Bash|grep KEY .en[v]
block|Bash|cat .e?v
block|Bash|cat {.e,x}nv
block|Bash|cat apps/{web,backend}/.env
block|Bash|F=.env; cat "$F"
block|Bash|git show HEAD:.env
block|Bash|cat $'\x2eenv'
block|Bash|cat .git/config
block|Bash|cat /proc/self/environ
block|Read|.git/config
block|Read|/proc/self/environ
allow|Bash|ls *
allow|Bash|echo {a,b}.md
allow|Bash|git log --oneline
allow|Bash|cat .gitignore
allow|Read|.github/workflows/ci.yml
# --- CI: gh pr/issue bodies only from files inside the repo
block@ci|Bash|gh pr comment 7⏎--body-file /proc/self/environ
block@ci|Bash|gh pr comment 7 \⏎  --body-file .git/config
block@ci|Bash|gh pr comment 7 --body-file $PWD/.git/config
block@ci|Bash|gh pr comment 7 --body-file "${GITHUB_WORKSPACE}/x.md"
block@ci|Bash|gh pr comment 7 --body-file .//.git/config
block@ci|Bash|gh pr comment 7 --body-file ././.git/config
block@ci|Bash|gh pr comment 7 --body-file docs/../../etc/passwd
block@ci|Bash|gh pr comment 7 --body-file docs/*.md
block@ci|Bash|gh pr comment 7 --body "$(cat README.md)"
block@ci|Bash|gh pr comment 7 --body "`cat README.md`"
allow@ci|Bash|gh pr comment 7 --body 'see `docs/x.md` and `pnpm test`'
allow|Bash|gh pr comment 7 --body "$(cat /tmp/review.md)"
block@ci|Bash|gh pr comment 7 --body-file .git/config
block@ci|Bash|gh pr comment 7 --body-file=/proc/self/environ
block@ci|Bash|gh pr comment 7 -F /home/runner/.config/gh/hosts.yml
block@ci|Bash|gh issue comment 7 -F../secrets.txt
block@ci|Bash|gh pr comment 7 --body-file ~/notes.md
block@ci|Bash|gh pr comment 7 --body-file -
allow@ci|Bash|gh pr comment 7 --body-file .ai-review.md
allow@ci|Bash|gh pr comment 7 --body-file ./.ai-review.md
allow@ci|Bash|gh issue comment 12 --body-file docs/specs/12-checkout.md
allow@ci|Bash|gh pr create --title t --body-file docs/plans/12.md
allow|Bash|gh pr create --title t --body-file /tmp/pr-body.md
allow@ci|Bash|git commit -F /tmp/msg.txt
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
