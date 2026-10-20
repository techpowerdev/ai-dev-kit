#!/usr/bin/env bash
# Usage: scripts/deploy.sh <preview|staging|production> <ref-or-name>
# Contract: must write "url=<deployed-url>" to $GITHUB_OUTPUT.
# The placeholder below also writes "configured=false" so workflows skip smoke tests,
# AI QA and production instead of testing a fake URL. Delete that line in your
# implementation (anything other than "false" counts as a real deploy).
#
# TODO: replace the body with your host's CLI. Examples:
#   Vercel  : url=$(npx vercel deploy --prebuilt --token "$DEPLOY_TOKEN" ${PROD_FLAG})
#   Railway : railway up --service backend --environment "$TARGET"
#   Render  : curl -s -X POST "$RENDER_DEPLOY_HOOK"
#   Fly.io  : flyctl deploy --app "myshop-$TARGET" --image-label "$REF"
# Backend (Medusa) migrations: run them as a separate, explicit step of the deploy
# for staging/production, never from the AI.
set -euo pipefail

TARGET="${1:?target required: preview|staging|production}"
REF="${2:?ref/name required}"

echo "Deploying $REF to $TARGET ..."

case "$TARGET" in
  preview)    URL="https://${REF}.preview.example.com" ;;
  staging)    URL="https://staging.example.com" ;;
  production) URL="https://www.example.com" ;;
  *) echo "unknown target $TARGET" >&2; exit 1 ;;
esac

echo "::warning::scripts/deploy.sh is a placeholder — implement it for your hosting provider."
echo "url=$URL" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "configured=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"   # ← remove when implemented
