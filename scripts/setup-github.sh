#!/usr/bin/env bash
# One-time GitHub setup for the AI + human-in-the-loop workflow.
# Requires: gh CLI logged in as a repo admin, jq.
# Usage: scripts/setup-github.sh owner/repo your-github-username [--solo]
#
#   (default)  Team mode: every PR needs 1 approval + CODEOWNERS review.
#              Admins can still bypass in an emergency.
#   --solo     One-person repo: GitHub never lets you approve your own PR, so no
#              approval is required. You must still open a PR and get green CI, and
#              the rules apply to admins too (no bypass). Production deploys still
#              wait for you to click "Approve and deploy" (Gate 4).
#
# Plan limits: environment required reviewers (Gate 4) and wait timers work only on
# public repos, or on private repos with GitHub Enterprise. On a private repo with
# GitHub Free, Pro or Team, GitHub does not enforce them. This script warns about it.
# https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
#
# Safe to re-run: every call is an idempotent PUT/PATCH.
set -euo pipefail

usage="usage: setup-github.sh owner/repo reviewer-username [--solo]"
REPO="${1:?$usage}"
REVIEWER="${2:?$usage}"
MODE="team"
case "${3:-}" in
  "")     ;;
  --solo) MODE="solo" ;;
  *)      echo "$usage" >&2; exit 1 ;;
esac
echo "==> Mode: $MODE"

echo "==> Labels"
label() { gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null; echo "   $1"; }
label "ai:spec"            "7057ff" "AI: write spec for this issue"
label "status:spec-review" "fbca04" "👤 Gate 1: waiting for human to approve spec"
label "approved:spec"      "0e8a16" "👤 Human approved spec → AI plans/builds"
label "approved:plan"      "0e8a16" "👤 Human approved plan (high-risk) → AI builds"
label "risk:low"           "c2e0c6" "Low risk change"
label "risk:medium"        "fef2c0" "Medium risk change"
label "risk:high"          "b60205" "High risk: payment/checkout/order/pricing/auth/migration"
label "type:feature"       "a2eeef" "Feature"
label "type:bug"           "d73a4a" "Bug"
label "hotfix"             "e11d21" "Production hotfix"
label "deploy-report"      "bfdadc" "AI post-deploy report"
label "incident"           "b60205" "Production incident"
label "area:storefront"    "ededed" ""
label "area:backend"       "ededed" ""
label "area:vendor"        "ededed" ""
label "dependencies"       "0366d6" ""

echo "==> Branch protection on main"
# Required CI checks only make sense once the repo has an app to build. Without a root
# package.json every CI run fails at "pnpm install", so requiring it would lock main.
if gh api "repos/$REPO/contents/package.json" >/dev/null 2>&1; then
  STATUS_CHECKS='{ "strict": true, "contexts": ["lint · typecheck · test · build", "e2e (Playwright)"] }'
  checks_msg="green CI required"
else
  STATUS_CHECKS='null'
  checks_msg="CI NOT required yet"
  echo "   ⚠️  No package.json on the default branch — skipping required status checks."
  echo "       Re-run this script after the app code is in to turn them on."
fi

if [[ "$MODE" == "solo" ]]; then
  REVIEWS='{ "required_approving_review_count": 0, "require_code_owner_reviews": false, "dismiss_stale_reviews": false, "require_last_push_approval": false }'
  ENFORCE_ADMINS=true
  reviews_msg="PR required, no approval (solo), rules apply to admins"
else
  REVIEWS='{ "required_approving_review_count": 1, "require_code_owner_reviews": true, "dismiss_stale_reviews": true, "require_last_push_approval": true }'
  ENFORCE_ADMINS=false
  reviews_msg="PR + 1 approval + CODEOWNERS"
fi

gh api -X PUT "repos/$REPO/branches/main/protection" --input - >/dev/null <<JSON
{
  "required_status_checks": $STATUS_CHECKS,
  "enforce_admins": $ENFORCE_ADMINS,
  "required_pull_request_reviews": $REVIEWS,
  "restrictions": null,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true
}
JSON
echo "   main: $reviews_msg, $checks_msg, no force push"

echo "==> Environments"
REVIEWER_ID=$(gh api "users/$REVIEWER" --jq .id)
VISIBILITY=$(gh api "repos/$REPO" --jq .visibility)
GATE4_OFF=false
if [[ "$VISIBILITY" == "private" ]]; then
  echo "   ⚠️  $REPO is $VISIBILITY. Required reviewers (Gate 4) and wait timers only work on"
  echo "       public repos or with GitHub Enterprise. On Free, Pro or Team, production deploys"
  echo "       will NOT wait for approval and the post-deploy report will not wait 30 minutes."
fi
gh api -X PUT "repos/$REPO/environments/preview" >/dev/null
gh api -X PUT "repos/$REPO/environments/staging" --input - >/dev/null <<JSON
{ "deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false } }
JSON
# prevent_self_review stays false so a solo maintainer can approve their own deploy.
# In a team, consider setting it to true so the person who merged is not the one who ships.
# Creates an environment with its protection rules. Only one failure is tolerated: on a
# non-public repo, GitHub may answer 422 because the plan does not include the rules.
# Then the environment is created without them and the caller is told (return 1).
# Any other failure (auth, network, a reviewer without access, a 422 on a public repo)
# shows GitHub's error and stops the script, so Gate 4 is never dropped silently.
put_env() {  # put_env <name> <json-with-rules> <json-without-rules>
  local err
  if err="$(gh api -X PUT "repos/$REPO/environments/$1" --input - 2>&1 >/dev/null <<<"$2")"; then
    return 0
  fi
  if [[ "$VISIBILITY" == "private" && "$err" == *"HTTP 422"* ]]; then
    echo "   ⚠️  GitHub rejected the protection rules for '$1' on this private repo (likely the plan limit):"
    echo "       $err"
    if ! gh api -X PUT "repos/$REPO/environments/$1" --input - >/dev/null <<<"$3"; then
      echo "   ✗ Could not create '$1' even without protection rules." >&2
      exit 1
    fi
    echo "       Created '$1' without them."
    GATE4_OFF=true
    return 1
  fi
  echo "   ✗ Could not create environment '$1' with its protection rules:" >&2
  echo "     $err" >&2
  exit 1
}
BRANCHES='"deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false }'
if put_env production \
  "{ \"wait_timer\": 0, \"prevent_self_review\": false, \"reviewers\": [ { \"type\": \"User\", \"id\": $REVIEWER_ID } ], $BRANCHES }" \
  "{ $BRANCHES }"; then
  if [[ "$VISIBILITY" == "public" ]]; then
    echo "   production: requires approval from @$REVIEWER (👤 Gate 4)"
  else
    echo "   production: reviewer @$REVIEWER set, but see the warning above (may not be enforced)"
  fi
fi
# Holds the AI post-deploy report for 30 min of real traffic without occupying a runner.
if put_env post-deploy-report "{ \"wait_timer\": 30, $BRANCHES }" "{ $BRANCHES }"; then
  echo "   post-deploy-report: 30 min wait timer before the AI health report"
fi

echo "==> Repo settings"
gh api -X PATCH "repos/$REPO" -f delete_branch_on_merge=true -f allow_squash_merge=true \
  -f allow_merge_commit=false -f allow_rebase_merge=false >/dev/null

echo
if [[ "$GATE4_OFF" == true || "$VISIBILITY" == "private" ]]; then
  echo "⚠️  Gate 4 (approval before production) is NOT enforced on this repo. See the warnings above"
  echo "   and docs/getting-started.md step 0 before setting PRODUCTION_DEPLOY_TOKEN."
  echo
fi
echo "✅ Done. Remaining manual steps:"
echo "  1. Install the Claude GitHub App:  https://github.com/apps/claude"
echo "  2. Add ONE Claude credential (AI jobs skip with a warning until one is set):"
echo "       gh secret set ANTHROPIC_API_KEY --repo $REPO         # Console API key, billed per token"
echo "       gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo $REPO   # or: subscription token from 'claude setup-token'"
echo "     (+ PREVIEW_DEPLOY_TOKEN, STAGING_DEPLOY_TOKEN, PRODUCTION_DEPLOY_TOKEN in their environments,"
echo "        SENTRY_READ_TOKEN for post-deploy reports)"
echo "  3. Replace @your-github-username in .github/CODEOWNERS"
echo "  4. Implement scripts/deploy.sh for your hosting provider"
echo "  5. Fill the TODOs in CLAUDE.md"
