#!/usr/bin/env bash
#
# Smoke test: openclaw-attest plugin with a live OpenClaw instance
#
# Run this inside a `script` session to record everything:
#   script -q ~/repos/openclaw-attest/docs/smoke-test-recording.txt bash docs/smoke-test.sh
#
# Prerequisites:
#   - ANTHROPIC_API_KEY set in environment
#   - pnpm build already run
#
set -euo pipefail

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: ANTHROPIC_API_KEY not set. Run: export ANTHROPIC_API_KEY=sk-ant-..."
  exit 1
fi

OPENCLAW="npx --yes openclaw"

echo "=== 1. Setting up isolated dev environment ==="
$OPENCLAW --dev onboard --non-interactive --accept-risk --skip-health \
  --auth-choice anthropic-api-key \
  --anthropic-api-key "$ANTHROPIC_API_KEY"

echo ""
echo "=== 2. Installing openclaw-attest plugin (linked) ==="
$OPENCLAW --dev plugins install . --link

echo ""
echo "=== 3. Verifying plugin is installed ==="
$OPENCLAW --dev plugins list

echo ""
echo "=== 4. Starting gateway in background ==="
$OPENCLAW --dev gateway --verbose --auth none &
GATEWAY_PID=$!
sleep 5  # give gateway time to start

echo ""
echo "=== 5. Triggering tool calls + querying receipts ==="
$OPENCLAW --dev agent --agent main --message "List the files in /tmp. Then use the attest_query_receipts tool to show me the audit trail, and finally use attest_verify_chain to verify the chain integrity."

echo ""
echo "=== 6. Shutting down gateway ==="
kill $GATEWAY_PID 2>/dev/null || true
wait $GATEWAY_PID 2>/dev/null || true

echo ""
echo "=== Done! Check ~/.openclaw-dev/attest/ for receipts.db ==="
