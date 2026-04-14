#!/usr/bin/env bash
# Run typecheck and tests before git push.
# Exit 0: all passed. Exit 2: failed.

set -Eeuo pipefail

fail() {
  echo "$1" >&2
  exit 2
}

trap 'fail "Hook failed unexpectedly — fix before pushing."' ERR

# Only run for git push commands.
input=$(cat)
command=$(echo "$input" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"//')
if [[ "$command" != git\ push* ]]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}" || fail "Failed to enter project directory."

echo "Running typecheck..." >&2
pnpm run typecheck >&2 || fail "Typecheck failed — fix before pushing."

echo "Running tests..." >&2
pnpm test >&2 || fail "Tests failed — fix before pushing."

exit 0
