#!/usr/bin/env bash
# pnpm lint — lints the kit itself.
#   - actionlint: every workflow (also shellchecks `run:` blocks when shellcheck is installed)
#   - shellcheck: every shell script
# Tools are not npm dependencies: actionlint is downloaded once at a pinned version and
# verified by SHA-256; shellcheck is preinstalled on GitHub's ubuntu runners.
set -euo pipefail
cd "$(dirname "$0")/../.."

ACTIONLINT_VERSION=1.7.12
# SHA-256 from the release's checksums file. Plain `case` because macOS ships bash 3.2.
actionlint_sha256() {
  case "$1" in
    darwin_amd64) echo 5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644 ;;
    darwin_arm64) echo aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f ;;
    linux_amd64)  echo 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 ;;
    linux_arm64)  echo 325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6 ;;
  esac
}

ensure_actionlint() {
  local os arch platform dir tgz expected actual
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"; arch="${arch/x86_64/amd64}"; arch="${arch/aarch64/arm64}"
  platform="${os}_${arch}"
  expected="$(actionlint_sha256 "$platform")"
  [[ -n "$expected" ]] || { echo "lint: no pinned actionlint for $platform" >&2; exit 1; }

  dir="node_modules/.cache/kit-tools/actionlint-$ACTIONLINT_VERSION"
  if [[ ! -x "$dir/actionlint" ]]; then
    mkdir -p "$dir"
    tgz="$dir/actionlint.tar.gz"
    curl -fsSL -o "$tgz" \
      "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_${platform}.tar.gz"
    if command -v sha256sum >/dev/null; then actual="$(sha256sum "$tgz" | cut -d' ' -f1)"
    else actual="$(shasum -a 256 "$tgz" | cut -d' ' -f1)"; fi
    if [[ "$actual" != "$expected" ]]; then
      rm -f "$tgz"; echo "lint: actionlint checksum mismatch ($actual)" >&2; exit 1
    fi
    tar -xzf "$tgz" -C "$dir" actionlint
    rm -f "$tgz"
  fi
  echo "$dir/actionlint"
}

shell_scripts() { git ls-files -co --exclude-standard -- '*.sh'; }

status=0

echo "==> actionlint"
"$(ensure_actionlint)" -color || status=1

echo "==> shellcheck"
if command -v shellcheck >/dev/null; then
  # shellcheck disable=SC2046  # word splitting is intended: one arg per file
  shellcheck -x $(shell_scripts) || status=1
elif [[ "${CI:-}" == "true" ]]; then
  echo "lint: shellcheck is required in CI but not installed" >&2; status=1
else
  echo "   ⚠️  shellcheck not installed — skipped locally (brew install shellcheck). CI always runs it."
fi

exit "$status"
