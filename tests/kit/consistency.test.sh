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
done < <(grep -rhoE --include='*.yml' '[Uu]se the [a-z-]+ agent' .github/workflows | awk '{print $3}' | sort -u)

# --- Slash commands --------------------------------------------------------------
# Commands that delegate must tell Claude to wait for subagents; in CI a background
# agent is killed when the main turn ends and its work is silently lost.
for f in .claude/commands/*.md; do
  if grep -qE '\*\*[a-z-]+-?[a-z]*\*\*' "$f" && grep -qiE 'delegate' "$f"; then
    expect "$f delegates but does not require foreground subagents" grep -q 'Run every delegation in the foreground' "$f"
  fi
done
bg_off="$(grep -rhc --include='*.yml' 'CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: "1"' .github/workflows | awk '{s+=$1} END {print s}')"
claude_runs="$(grep -rhc --include='*.yml' 'anthropics/claude-code-action@' .github/workflows | awk '{s+=$1} END {print s}')"
expect "every Claude step disables background tasks ($bg_off of $claude_runs)" test "$bg_off" -eq "$claude_runs"
for f in .claude/commands/*.md; do
  if grep -q 'Run every delegation in the foreground' "$f"; then
    expect "$f tells Claude to run shell commands one at a time" grep -q 'Run each shell command on its own' "$f"
  fi
done
# AI pipeline: every job checks it produced something, and /implement pushes step by step.
pipeline_claude="$(grep -c 'anthropics/claude-code-action@' .github/workflows/ai-pipeline.yml)"
# shellcheck disable=SC2016  # literal text to match, not an expansion
pipeline_checks="$(grep -c 'check-pipeline-result.sh" "$ISSUE_NUMBER"' .github/workflows/ai-pipeline.yml || true)"
expect "every ai-pipeline Claude job checks it produced a result ($pipeline_checks of $pipeline_claude)" test "$pipeline_checks" -eq "$pipeline_claude"
pb_block="$(sed -n '/^  plan-and-build:/,/^  build-high-risk:/p' .github/workflows/ai-pipeline.yml)"
# shellcheck disable=SC2016  # literal text to match
expect "plan-and-build checks in build mode (the plan comment alone is not a result)" grep -q '"$PIPELINE_STARTED_AT" build$' <<<"$pb_block"
expect "/implement pushes after every plan step" grep -q 'then push right away' .claude/commands/implement.md
expect "/implement resumes from an existing ai/<n>-* branch" grep -q 'continue from it' .claude/commands/implement.md
# shellcheck disable=SC2016  # literal text to match, not an expansion
expect "/implement runs tests through pnpm only" grep -q 'Use these `pnpm` scripts only' .claude/commands/implement.md
expect "/plan always posts the plan on the issue" grep -q 'whatever the risk level' .claude/commands/plan.md
expect "claude-review.yml checks that the review was posted" grep -q 'check-review-posted.sh' .github/workflows/claude-review.yml
# shellcheck disable=SC2016  # backticks here are literal Markdown, not command substitution
expect "/review posts the comment from a file, not inline --body" grep -q -- '--body-file .ai-review.md' .claude/commands/review.md
review_tools="$(grep -h -- '--allowedTools' .github/workflows/claude-review.yml)"
expect "AI review may write its comment file" grep -qF 'Edit(./.ai-review.md),Write(./.ai-review.md)' <<<"$review_tools"
broad="$(grep -oE '[",](Write|Edit|MultiEdit)[,"]' <<<"$review_tools" || true)"
expect "AI review has no broader Write/Edit permission: $broad" none "$broad"
expect "AI review refuses a committed .ai-review.md" grep -q 'git ls-files --error-unmatch .ai-review.md' .github/workflows/claude-review.yml
# shellcheck disable=SC2016  # backticks here are literal Markdown, not command substitution
expect "/review tells Claude to start the comment with the marker the check looks for" grep -q 'start with the line `## AI Review`' .claude/commands/review.md
# shellcheck disable=SC2016  # backticks here are literal Markdown, not command substitution
compound="$(grep -rnE '`[^`]*(&&|\|\|)[^`]*`' .claude/commands .claude/agents | grep -v 'without `;`, `&&`' || true)"
expect "no command or agent tells Claude to run a compound shell command: $compound" none "$compound"
while read -r c; do
  expect "a workflow runs missing command '/$c'" test -f ".claude/commands/$c.md"
done < <(grep -rhoE --include='*.yml' 'prompt: "/[a-z-]+' .github/workflows | sed 's|.*/||' | sort -u)

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
unpinned="$(grep -rnE --include='*.yml' 'uses: [^. ][^@ ]*@' .github/workflows | grep -vE '@[0-9a-f]{40}( |$)' || true)"
expect "every third-party action is pinned to a commit SHA: $unpinned" none "$unpinned"
dangerous="$(grep -rhE --include='*.yml' 'allowedTools' .github/workflows | grep -oE 'pr merge|release create|push --force|push -f' || true)"
expect "no workflow lets Claude merge, release, or force-push: $dangerous" none "$dangerous"
for job in spec plan-and-build build-high-risk; do
  block="$(sed -n "/^  $job:/,/^  [a-z]/p" .github/workflows/ai-pipeline.yml)"
  expect "ai-pipeline job '$job' ignores label events from bots" grep -qF "sender.type != 'Bot'" <<<"$block"
done
hook="$(node -e 'const s=require("./.claude/settings.json");console.log(s.hooks.PreToolUse[0].hooks[0].command)' | awk '{print $NF}')"
expect "settings.json hook '$hook' exists and is executable" test -x "$hook"
expect "guard.sh fails closed: unexpected exit codes become a block" grep -q 'rc=2' .claude/hooks/guard.sh
matcher="$(node -e 'const s=require("./.claude/settings.json");console.log(s.hooks.PreToolUse[0].matcher)')"
for t in Bash Read Grep Glob Edit Write MultiEdit NotebookEdit; do
  expect "the guard hook runs for $t (matcher: $matcher)" grep -qE "(^|\\|)$t(\\||$)" <<<"$matcher"
done
for wf in claude-review preview deploy; do
  expect "$wf.yml: the Claude job's checkout does not persist credentials" grep -q 'persist-credentials: false' ".github/workflows/$wf.yml"
done

# --- deploy.sh contract -------------------------------------------------------------
out="$(mktemp)"; trap 'rm -f "$out"' EXIT
for target in preview staging production; do
  : >"$out"
  GITHUB_OUTPUT="$out" bash scripts/deploy.sh "$target" test-ref >/dev/null 2>&1 || true
  expect "deploy.sh $target writes url=... to GITHUB_OUTPUT" grep -qE '^url=https?://' "$out"
done

# Placeholder deploy.sh must say it is not configured, so nothing tests a fake URL.
: >"$out"; GITHUB_OUTPUT="$out" bash scripts/deploy.sh staging test-ref >/dev/null 2>&1 || true
expect "placeholder deploy.sh reports configured=false" grep -qx 'configured=false' "$out"
job_block() { sed -n "/^  $2:/,/^  [a-z]/p" ".github/workflows/$1"; }
for jw in "deploy.yml smoke-staging staging" "preview.yml ai-qa deploy-preview" "deploy.yml post-deploy-report production"; do
  read -r wf job dep <<<"$jw"
  expect "$wf job '$job' is skipped when '$dep' is not configured" \
    grep -qF "needs.$dep.outputs.configured != 'false'" <<<"$(job_block "$wf" "$job")"
done
expect "production smoke test is skipped when not configured" \
  grep -qF "steps.deploy.outputs.configured != 'false'" <<<"$(job_block deploy.yml production)"

# Every Claude step outside the human-triggered workflows skips cleanly without an API key.
for jw in "claude-review.yml review" "preview.yml ai-qa" "deploy.yml post-deploy-report"; do
  read -r wf job <<<"$jw"
  block="$(job_block "$wf" "$job")"
  # the step's own lines, from its "- " line down to the uses: line
  gated="$(awk '/^      - /{step=""} {step=step $0 "\n"} /anthropics\/claude-code-action@/{printf "%s", step; exit}' <<<"$block")"
  expect "$wf job '$job' runs Claude only when a Claude credential is set" grep -qF "env.HAS_CLAUDE_AUTH == 'true'" <<<"$gated"
done
# Every Claude step accepts either credential, so a repo can use an API key or a subscription token.
claude_steps="$(grep -rc --include='*.yml' 'anthropics/claude-code-action@' .github/workflows | awk -F: '{s+=$2} END {print s}')"
# shellcheck disable=SC2016  # the ${{ }} below are literal GitHub expressions to match, not shell
api_inputs="$(grep -rc --include='*.yml' 'anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}' .github/workflows | awk -F: '{s+=$2} END {print s}')"
# shellcheck disable=SC2016  # the ${{ }} below are literal GitHub expressions to match, not shell
oauth_inputs="$(grep -rc --include='*.yml' 'claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}' .github/workflows | awk -F: '{s+=$2} END {print s}')"
expect "all $claude_steps Claude steps pass ANTHROPIC_API_KEY (found $api_inputs)" test "$api_inputs" -eq "$claude_steps"
expect "all $claude_steps Claude steps pass CLAUDE_CODE_OAUTH_TOKEN (found $oauth_inputs)" test "$oauth_inputs" -eq "$claude_steps"
# Every Claude step has id "claude" and is followed by the step that prints why it failed.
ids="$(grep -rhcE --include='*.yml' '^ +id: claude$' .github/workflows | awk '{s+=$1} END {print s}')"
# shellcheck disable=SC2016  # literal "$EXEC_FILE" as written in the workflows
shows="$(grep -rc --include='*.yml' '"$RUNNER_TEMP/show-claude-error.sh" "$EXEC_FILE"' .github/workflows | awk -F: '{s+=$2} END {print s}')"
expect "all $claude_steps Claude steps have id: claude (found $ids)" test "$ids" -eq "$claude_steps"
expect "all $claude_steps Claude steps are followed by show-claude-error.sh (found $shows)" test "$shows" -eq "$claude_steps"
snaps="$(grep -rc --include='*.yml' 'name: Snapshot CI helpers' .github/workflows | awk -F: '{s+=$2} END {print s}')"
expect "all $claude_steps Claude steps snapshot the CI helpers first (found $snaps)" test "$snaps" -eq "$claude_steps"
direct="$(grep -rn --include='*.yml' 'bash scripts/\(show-claude-error\|check-review-posted\)' .github/workflows || true)"
expect "helpers run from the snapshot, not the working tree: $direct" none "$direct"
# The skip gates must accept either credential, or a token-only repo would skip every AI job.
while IFS= read -r gate; do
  expect "HAS_CLAUDE_AUTH checks both credentials: $gate" grep -qE 'ANTHROPIC_API_KEY.*CLAUDE_CODE_OAUTH_TOKEN' <<<"$gate"
done < <(grep -rh --include='*.yml' 'HAS_CLAUDE_AUTH:' .github/workflows)

echo "   consistency: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
