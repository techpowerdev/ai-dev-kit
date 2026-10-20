#!/usr/bin/env bash
# pnpm typecheck — the kit has no TypeScript, so this checks that every config file parses:
#   - shell scripts:  bash -n
#   - JSON:           node
#   - YAML:           ruby (preinstalled on macOS and GitHub's ubuntu runners)
set -euo pipefail
cd "$(dirname "$0")/../.."

status=0
fail() { echo "   ✗ $1" >&2; status=1; }

echo "==> shell syntax"
while IFS= read -r f; do bash -n "$f" || fail "$f"; done < <(git ls-files -co --exclude-standard -- '*.sh')

echo "==> JSON"
while IFS= read -r f; do
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$f" || fail "$f"
done < <(git ls-files -co --exclude-standard -- '*.json')

echo "==> YAML"
if command -v ruby >/dev/null; then
  while IFS= read -r f; do
    ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$f" || fail "$f"
  done < <(git ls-files -co --exclude-standard -- '*.yml' '*.yaml')
elif [[ "${CI:-}" == "true" ]]; then
  fail "ruby is required in CI to parse YAML"
else
  echo "   ⚠️  ruby not installed — YAML skipped locally (actionlint still covers workflows)."
fi

exit "$status"
