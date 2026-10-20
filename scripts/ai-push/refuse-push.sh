#!/usr/bin/env bash
# Usage: refuse-push.sh --number N --reason fork|not-ai-branch|issue|high-risk [--slug OWNER/REPO]
# Env: GH_TOKEN — must be github.token (comments then come from github-actions[bot],
#      which cannot trigger @-mention workflows), GITHUB_REPOSITORY (or --slug)
#
# Trusted. Explains on the PR or issue why the AI's commits were not pushed. Posts a
# fixed message (no text from the Claude job), pushes nothing, creates no branch,
# exits 0.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ai-push/lib.sh
source "$here/lib.sh"

number=""; reason=""; slug="${GITHUB_REPOSITORY:-}"
while (( $# )); do
  case "$1" in
    --number) number="$2"; shift 2 ;;
    --reason) reason="$2"; shift 2 ;;
    --slug) slug="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$number" =~ ^[0-9]+$ && -n "$slug" ]] || { echo "usage: see header" >&2; exit 2; }

case "$reason" in
  fork)          why="PR นี้มาจาก fork ซึ่ง AI ไม่มีสิทธิ์ push ไปที่ branch นั้น" ;;
  not-ai-branch) why="branch ของ PR นี้ไม่ได้ชื่อ \`ai/<issue>-<slug>\` AI push ได้เฉพาะ branch ของ AI เพื่อไม่ไปแก้ branch ของคน" ;;
  issue)         why="การ mention Claude บน issue ธรรมดาทำได้แค่ตอบ comment (decision 8.1) ถ้าต้องการให้ AI เขียนโค้ด ให้ใช้ label \`ai:spec\` แทน" ;;
  high-risk)     why="การเปลี่ยนแปลงแตะ path ความเสี่ยงสูง (ตาม \`.github/labeler.yml\`) แต่ issue ยังไม่ผ่าน Gate 1b ให้คนอนุมัติ plan ด้วย label \`approved:plan\` แล้วรันใหม่" ;;
  *) echo "unknown reason: $reason" >&2; exit 2 ;;
esac

body="$(mktemp)"; trap 'rm -f "$body"' EXIT
cat >"$body" <<EOF
⚠️ **AI ไม่ได้ push การเปลี่ยนแปลงในรอบนี้**

$why

ไม่มี branch ใหม่และไม่มีอะไรถูก push ดู log ของ workflow run นี้เพื่อดู commit ที่ AI ทำไว้
EOF
gh issue comment "$number" --repo "$slug" --body-file "$body" >/dev/null || ai_warn "Could not post the explanation on #$number."
echo "Refused to push for #$number ($reason)."
