#!/usr/bin/env bash
# Build the Path-A proof: a Swift AppKit app that hosts a ScintillaView via
# the Obj-C++ shim in Bridge/.
#
# Inputs (prebuilt by xcodebuild on the ScintillaTest project):
#   - Scintilla.framework
#   - liblexilla.dylib  (not used yet, but lives in the same dir)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORKS="${SCI_FRAMEWORKS:-$HOME/Library/Developer/Xcode/DerivedData/ScintillaTest-evnleelvldrbxydcxfmzyporyjyb/Build/Products/Debug}"
OUT="$HERE/build"

if [ ! -d "$FRAMEWORKS/Scintilla.framework" ]; then
  echo "Scintilla.framework not found at $FRAMEWORKS" >&2
  echo "Build ScintillaTest first, or set SCI_FRAMEWORKS=." >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

LEXILLA_INC="$HERE/../lexilla/include"

# 1. Compile the Obj-C++ shim into a .o.
clang++ -c "$HERE/Bridge/SciTextView.mm" \
  -fobjc-arc \
  -fmodules \
  -std=c++17 \
  -F "$FRAMEWORKS" \
  -I "$LEXILLA_INC" \
  -o "$OUT/SciTextView.o"

# 2. Compile + link Swift main, linking the .o and the framework.
swiftc "$HERE/Sources/main.swift" \
  -import-objc-header "$HERE/Bridge/SciTextView.h" \
  -F "$FRAMEWORKS" \
  -framework Scintilla \
  -framework Cocoa \
  -Xlinker "$OUT/SciTextView.o" \
  -Xlinker -lc++ \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -o "$OUT/SciProof"

echo "Built $OUT/SciProof"
