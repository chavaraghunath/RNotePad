#!/bin/bash
# SPDX-License-Identifier: MIT
# Run the full SourceGraph test suite (3 tiers). Exits non-zero on any failure.
#
#   Tier 1  unit      — graph model + query logic (standalone swiftc)
#   Tier 2  protocol  — MCP JSON-RPC server, all 8 tools + error paths (real binary)
#   Tier 3  e2e       — build graph from a real indexed workspace
#
# Requires a built app at Sourcepad/dist/Sourcepad.app for tiers 2–3.
# Override the e2e workspace with SOURCEPAD_TEST_WORKSPACE=/path.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0

echo "── Tier 1: unit (model + queries) ─────────────────────────"
bash "$DIR/run-tests.sh" || fail=1

echo "── Tier 2: MCP protocol (real binary) ─────────────────────"
python3 "$DIR/mcp_protocol_test.py" || fail=1

echo "── Tier 3: end-to-end (real indexed workspace) ────────────"
if [ -n "$(ls "$HOME/Library/Application Support/Sourcepad/Workspaces/"*.db 2>/dev/null)" ]; then
  python3 "$DIR/workspace_e2e_test.py" || fail=1
else
  echo "  skipped — no indexed workspace found"
fi

echo "───────────────────────────────────────────────────────────"
[ "$fail" -eq 0 ] && echo "ALL SOURCEGRAPH TESTS PASSED" || echo "SOURCEGRAPH TESTS FAILED"
exit $fail
