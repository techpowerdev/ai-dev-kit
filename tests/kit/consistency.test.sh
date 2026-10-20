#!/usr/bin/env bash
# Checks that the pieces of the AI workflow still point at each other correctly.
# A rename in one place (an agent, a label, a CI job name) silently breaks a flow
# somewhere else; these checks catch that before merge.
set -euo pipefail
cd "$(dirname "$0")/../.."

pass=0; fail=0
# expect <description> <command...> — passes when the command succeeds
expect() {
  local desc="$1"; shift
  if "$@"; then pass=$((pass+1)); else fail=$((fail+1)); echo "   ✗ $desc"; fi
}
in_list() { grep -qxF "$1" <<<"$2"; }                 # in_list <item> <newline-separated list>
none()    { ! grep -q . <<<"$1"; }                     # none <text> — true when text is empty

# --- Agents --------------------------------------------------------------------
# Every agent file's frontmatter name matches its filename.
for f in .claude/agents/*.md; do
  n="$(sed -n 's/^name: *//p' "$f" | head -1)"
  expect "agent $f declares name '$n'" test "$n" = "$(basename "$f" .md)"
done
# Every agent a slash command delegates to (**name**) exists. low/medium/high are risk levels, not agents.
while read -r a; do
  expect "a command delegates to missing agent '$a'" test -f ".claude/agents/$a.md"
done < <(grep -rhoE '\*\*[a-z-]+\*\*' .claude/commands | tr -d '*' | grep -vxE 'low|medium|high' | sort -u)
# Agents named in workflow prompts ("Use the X agent") exist.
while read -r a; do
  expect "a workflow uses missing agent '$a'" test -f ".claude/agents/$a.md"
done < <(grep -rhoE '[Uu]se the [a-z-]+ agent' .github/workflows | awk '{print $3}' | sort -u)

# --- Slash commands --------------------------------------------------------------
while read -r c; do
  expect "a workflow runs missing command '/$c'" test -f ".claude/commands/$c.md"
done < <(grep -rhoE 'prompt: "/[a-z-]+' .github/workflows | sed 's|.*/||' | sort -u)

# --- Labels ------------------------------------------------------------------------
# Every label the workflow depends on is created by setup-github.sh.
created="$(sed -nE 's/^label "([^"]+)".*/\1/p' scripts/setup-github.sh)"
used="$(
  {
    grep -rhoE '\b(ai|approved|status|risk|type|area):[a-z]+(-[a-z]+)*\b' .github .claude/commands docs
    sed -nE 's/^"([^"]+)":$/\1/p' .github/labeler.yml
    grep -hoE 'labels: \[[^]]+\]' .github/dependabot.yml | grep -oE '"[^"]+"' | tr -d '"'
    printf '%s\n' deploy-report incident hotfix   # used in prose prompts
  } | sort -u
)"
while read -r l; do
  expect "label '$l' is used but not created by setup-github.sh" in_list "$l" "$created"
done <<<"$used"

# --- CI / branch protection ----------------------------------------------------------
# Required status checks must match real job names in ci.yml, or every PR waits forever.
ci_jobs="$(sed -nE 's/^    name: (.*)$/\1/p' .github/workflows/ci.yml)"
while read -r ctx; do
  expect "required check '$ctx' is not a job name in ci.yml" in_list "$ctx" "$ci_jobs"
done < <(grep -oE '"contexts": \[[^]]*\]' scripts/setup-github.sh | grep -oE '"[^"]+"' | tr -d '"' | grep -v contexts | sort -u)
# Reusable workflows that ci.yml calls must declare workflow_call.
while read -r wf; do
  expect "$wf is called from ci.yml but has no workflow_call trigger" grep -q "workflow_call:" "$wf"
done < <(sed -nE 's|^ *uses: \./(\.github/workflows/[^ ]+)$|\1|p' .github/workflows/ci.yml)

# --- Guardrails ---------------------------------------------------------------------
unpinned="$(grep -rnE 'uses: [^. ][^@ ]*@' .github/workflows | grep -vE '@[0-9a-f]{40}( |$)' || true)"
expect "every third-party action is pinned to a commit SHA: $unpinned" none "$unpinned"
dangerous="$(grep -rhE 'allowedTools' .github/workflows | grep -oE 'pr merge|release create|push --force|push -f' || true)"
expect "no workflow lets Claude merge, release, or force-push: $dangerous" none "$dangerous"
for job in spec plan-and-build build-high-risk; do
  block="$(sed -n "/^  $job:/,/^  [a-z]/p" .github/workflows/ai-pipeline.yml)"
  expect "ai-pipeline job '$job' ignores label events from bots" grep -qF "sender.type != 'Bot'" <<<"$block"
done
hook="$(node -e 'const s=require("./.claude/settings.json");console.log(s.hooks.PreToolUse[0].hooks[0].command)' | awk '{print $NF}')"
expect "settings.json hook '$hook' exists and is executable" test -x "$hook"

# --- deploy.sh contract -------------------------------------------------------------
out="$(mktemp)"; trap 'rm -f "$out"' EXIT
for target in preview staging production; do
  : >"$out"
  GITHUB_OUTPUT="$out" bash scripts/deploy.sh "$target" test-ref >/dev/null 2>&1 || true
  expect "deploy.sh $target writes url=... to GITHUB_OUTPUT" grep -qE '^url=https?://' "$out"
done

echo "   consistency: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
