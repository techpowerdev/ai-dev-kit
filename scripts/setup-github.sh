#!/usr/bin/env bash
# One-time GitHub setup for the AI + human-in-the-loop workflow.
# Requires: gh CLI logged in as a repo admin, jq.
# Usage: scripts/setup-github.sh owner/repo your-github-username
set -euo pipefail

REPO="${1:?usage: setup-github.sh owner/repo reviewer-username}"
REVIEWER="${2:?usage: setup-github.sh owner/repo reviewer-username}"

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
gh api -X PUT "repos/$REPO/branches/main/protection" --input - >/dev/null <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["lint · typecheck · test · build", "e2e (Playwright)"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "require_code_owner_reviews": true,
    "dismiss_stale_reviews": true,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true
}
JSON
echo "   main: PR + 1 approval + CODEOWNERS + green CI required, no force push"

echo "==> Environments"
REVIEWER_ID=$(gh api "users/$REVIEWER" --jq .id)
gh api -X PUT "repos/$REPO/environments/preview" >/dev/null
gh api -X PUT "repos/$REPO/environments/staging" --input - >/dev/null <<JSON
{ "deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false } }
JSON
gh api -X PUT "repos/$REPO/environments/production" --input - >/dev/null <<JSON
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [ { "type": "User", "id": $REVIEWER_ID } ],
  "deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false }
}
JSON
echo "   production: requires approval from @$REVIEWER (👤 Gate 4)"

echo "==> Repo settings"
gh api -X PATCH "repos/$REPO" -f delete_branch_on_merge=true -f allow_squash_merge=true \
  -f allow_merge_commit=false -f allow_rebase_merge=false >/dev/null

echo
echo "✅ Done. Remaining manual steps:"
echo "  1. Install the Claude GitHub App:  https://github.com/apps/claude"
echo "  2. Add secrets:  gh secret set ANTHROPIC_API_KEY --repo $REPO"
echo "     (+ PREVIEW_DEPLOY_TOKEN, STAGING_DEPLOY_TOKEN, PRODUCTION_DEPLOY_TOKEN in their environments,"
echo "        SENTRY_READ_TOKEN for post-deploy reports)"
echo "  3. Replace @your-github-username in .github/CODEOWNERS"
echo "  4. Implement scripts/deploy.sh for your hosting provider"
echo "  5. Fill the TODOs in CLAUDE.md"
