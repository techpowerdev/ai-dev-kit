#!/usr/bin/env bash
# Usage: check-pipeline-result.sh <issue-number> <started-at, e.g. 2026-10-20T18:13:16Z> [any|build]
# Env: GH_TOKEN, GITHUB_REPOSITORY, optional REVIEW_BOT (default claude[bot]), RUN_URL
#
# An AI pipeline job can end "successfully" with nothing to show for it: on the
# runner, unpushed work is deleted with the machine. This passes only if, since the
# job started, the bot commented on the issue (a spec, a plan, a progress or a
# "blocked" note) or a PR from a branch ai/<issue>-* was opened or updated.
# Otherwise it comments on the issue with a link to the run and fails.
#
# Mode "build" (plan-and-build): /plan always posts the plan, so on its own that is
# not enough when the plan then continues into /implement. Unless the issue has
# risk:high (the plan comment waiting at Gate 1b is the expected result), a "# Spec"
# or "# Plan" comment does not count: there must be a PR or another bot comment,
# such as /implement's progress or "blocked" note.
set -euo pipefail
issue="${1:?usage: check-pipeline-result.sh <issue-number> <started-at>}"
since="${2:?usage: check-pipeline-result.sh <issue-number> <started-at>}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
bot="${REVIEW_BOT:-claude[bot]}"
run="${RUN_URL:-the workflow run}"
mode="${3:-any}"
case "$mode" in any|build) ;; *) echo "unknown mode '$mode' (any|build)" >&2; exit 2 ;; esac

skip_docs=false
if [[ "$mode" == build ]]; then
  labels="$(gh api "repos/$repo/issues/$issue" --jq '[.labels[].name] | join(",")')"
  [[ ",$labels," == *",risk:high,"* ]] || skip_docs=true
fi

comments="$(gh api "repos/$repo/issues/$issue/comments" --paginate \
  | jq -s --arg since "$since" --arg bot "$bot" --argjson skip "$skip_docs" '
      [ .[] | if type == "array" then .[] else . end
        | select(.user.login == $bot and (.created_at // "") >= $since)
        | select(($skip | not) or ((.body // "") | test("^\\s*# (Spec|Plan)\\b") | not)) ] | length')"

prs="$(gh api "repos/$repo/pulls?state=all&sort=updated&direction=desc&per_page=100" \
  | jq --arg since "$since" --arg prefix "ai/$issue-" '
      [ .[] | select((.head.ref // "") | startswith($prefix))
              | select((.updated_at // "") >= $since) ] | length')"

if (( comments + prs > 0 )); then
  echo "AI pipeline produced a result for #$issue ($comments comment(s), $prs PR(s) updated)."
  exit 0
fi

echo "::error title=AI pipeline produced nothing::No comment on #$issue and no PR from ai/$issue-* since $since. Work that was not pushed is lost with the runner."
body="⚠️ The AI pipeline run ended without a result: no comment here and no PR from a branch \`ai/$issue-*\`. Anything it did that was not pushed is lost. See $run for the log, including tools that were denied."
gh issue comment "$issue" --repo "$repo" --body "$body" || echo "::warning::Could not post the failure comment on #$issue."
exit 1
