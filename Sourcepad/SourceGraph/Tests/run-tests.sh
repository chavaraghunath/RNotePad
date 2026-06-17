#!/bin/bash
# SPDX-License-Identifier: MIT
# Compile + run the standalone SourceGraph unit tests (model + query logic).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SG="$(dirname "$DIR")"
OUT="$(mktemp -d)/sgtests"

swiftc -O \
  "$SG/SourceGraphModel.swift" \
  "$SG/SourceGraphQueries.swift" \
  "$DIR/SourceGraphTests.swift" \
  -o "$OUT"

"$OUT"
