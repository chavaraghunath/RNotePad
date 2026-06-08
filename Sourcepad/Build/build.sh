#!/usr/bin/env bash
# Sourcepad — build script. Produces Sourcepad/dist/Sourcepad.app.
# Output dir is `dist/` (not `build/`) to avoid case-insensitive APFS collision
# with the source `Build/` directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"           # .../Sourcepad/Build
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"               # .../Sourcepad
REPO_ROOT="$(cd "$APP_DIR/.." && pwd)"                # repo root
BUILD_DIR="$APP_DIR/dist"
APP_BUNDLE="$BUILD_DIR/Sourcepad.app"
SCI_PROJ="$REPO_ROOT/scintilla/cocoa/ScintillaTest/ScintillaTest.xcodeproj"
LEXILLA_INC="$REPO_ROOT/lexilla/include"
TS_ROOT="$REPO_ROOT/tree-sitter"

# 1+2. Build Scintilla.framework + liblexilla.dylib
echo "==> Building Scintilla.framework + liblexilla.dylib"
xcodebuild -project "$SCI_PROJ" -scheme Scintilla -configuration Release \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tail -3
xcodebuild -project "$SCI_PROJ" -scheme lexilla -configuration Release \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tail -3

DD=~/Library/Developer/Xcode/DerivedData
SCI_BUILD=$(ls -dt "$DD"/ScintillaTest-*/Build/Products/Release | head -1)
if [ ! -d "$SCI_BUILD/Scintilla.framework" ]; then
    echo "error: Scintilla.framework not found at $SCI_BUILD" >&2
    exit 1
fi

# 3. Build the Obj-C++ bridge + the generated Obj-C keyword data.
echo "==> Compiling Obj-C++ bridge"
mkdir -p "$BUILD_DIR"
clang++ -c "$APP_DIR/Bridge/SciTextView.mm" \
    -fobjc-arc -fmodules -std=c++17 \
    -F "$SCI_BUILD" \
    -I "$LEXILLA_INC" \
    -I "$APP_DIR/Bridge" \
    -I "$TS_ROOT/lib/include" \
    -I "$TS_ROOT/grammars" \
    -mmacosx-version-min=13.0 \
    -o "$BUILD_DIR/SciTextView.o"

clang -c "$APP_DIR/Bridge/KeywordSetsGenerated.m" \
    -fobjc-arc -fmodules \
    -mmacosx-version-min=13.0 \
    -o "$BUILD_DIR/KeywordSetsGenerated.o"

# Tree-sitter: core library (single-file lib.c) + per-grammar parsers.
echo "==> Compiling Tree-sitter core + grammars"
TS_OBJS=()

clang -c "$TS_ROOT/lib/src/lib.c" \
    -O2 \
    -I "$TS_ROOT/lib/include" \
    -I "$TS_ROOT/lib/src" \
    -mmacosx-version-min=13.0 \
    -o "$BUILD_DIR/tree-sitter.o"
TS_OBJS+=("$BUILD_DIR/tree-sitter.o")

# Each grammar is one parser.c (and sometimes a scanner.c). Compile both.
for grammar_dir in "$TS_ROOT"/grammars/*/; do
    name="$(basename "$grammar_dir")"
    if [ -f "$grammar_dir/src/parser.c" ]; then
        clang -c "$grammar_dir/src/parser.c" \
            -O2 \
            -I "$grammar_dir/src" \
            -I "$TS_ROOT/lib/include" \
            -mmacosx-version-min=13.0 \
            -o "$BUILD_DIR/ts-$name-parser.o"
        TS_OBJS+=("$BUILD_DIR/ts-$name-parser.o")
    fi
    if [ -f "$grammar_dir/src/scanner.c" ]; then
        clang -c "$grammar_dir/src/scanner.c" \
            -O2 \
            -I "$grammar_dir/src" \
            -I "$TS_ROOT/lib/include" \
            -mmacosx-version-min=13.0 \
            -o "$BUILD_DIR/ts-$name-scanner.o"
        TS_OBJS+=("$BUILD_DIR/ts-$name-scanner.o")
    fi
done

# 4. Compile Swift sources
echo "==> Compiling Swift sources"
SWIFT_SRCS=(
    "$APP_DIR/App/main.swift"
    "$APP_DIR/App/AppDelegate.swift"
    "$APP_DIR/App/MainMenu.swift"
    "$APP_DIR/App/DebugLog.swift"
    "$APP_DIR/App/Preferences.swift"
    "$APP_DIR/App/PreferencesWindowController.swift"
    "$APP_DIR/App/SessionRestore.swift"
    "$APP_DIR/App/ClosedTabHistory.swift"
    "$APP_DIR/Workspace/Workspace.swift"
    "$APP_DIR/Workspace/WorkspaceManager.swift"
    "$APP_DIR/Workspace/ProjectIndex.swift"
    "$APP_DIR/Workspace/IndexerCoordinator.swift"
    "$APP_DIR/Workspace/WorkspaceIndexHost.swift"
    "$APP_DIR/Workspace/TodoAggregator.swift"
    "$APP_DIR/Palette/PaletteFuzzy.swift"
    "$APP_DIR/Palette/PaletteProvider.swift"
    "$APP_DIR/Palette/PaletteWindowController.swift"
    "$APP_DIR/Palette/FilePaletteProvider.swift"
    "$APP_DIR/Palette/CommandPaletteProvider.swift"
    "$APP_DIR/Palette/SymbolPaletteProvider.swift"
    "$APP_DIR/Editor/GoToLinePanel.swift"
    "$APP_DIR/Editor/AutoPair.swift"
    "$APP_DIR/Editor/CommentSyntax.swift"
    "$APP_DIR/Editor/Bookmarks.swift"
    "$APP_DIR/Search/FindInFilesEngine.swift"
    "$APP_DIR/Search/FindInFilesWindowController.swift"
    "$APP_DIR/Document/TextDocument.swift"
    "$APP_DIR/Document/DocumentController.swift"
    "$APP_DIR/Document/ExternalChangeWatcher.swift"
    "$APP_DIR/Document/GitDiffGutter.swift"
    "$APP_DIR/Editor/AutoComplete.swift"
    "$APP_DIR/Editor/EditorWindowController.swift"
    "$APP_DIR/Editor/EditorViewController.swift"
    "$APP_DIR/Editor/EditorContent.swift"
    "$APP_DIR/Editor/EditorContentFactory.swift"
    "$APP_DIR/Editor/PlaceholderContent.swift"
    "$APP_DIR/Views/CSVGridContent.swift"
    "$APP_DIR/Views/JSONTreeContent.swift"
    "$APP_DIR/Views/HexViewContent.swift"
    "$APP_DIR/Views/SQLiteBrowserContent.swift"
    "$APP_DIR/Editor/EditorPaneViewController.swift"
    "$APP_DIR/Editor/PreviewPaneViewController.swift"
    "$APP_DIR/Editor/SidebarTabBar.swift"
    "$APP_DIR/Editor/OutlineSidebarPanel.swift"
    "$APP_DIR/Editor/TasksSidebarPanel.swift"
    "$APP_DIR/Editor/SidebarViewController.swift"
    "$APP_DIR/Editor/StatusBarView.swift"
    "$APP_DIR/Editor/RootContentViewController.swift"
    "$APP_DIR/Editor/AppearanceForwardingView.swift"
    "$APP_DIR/Editor/FileDropOverlay.swift"
    "$APP_DIR/Editor/PreviewRenderer.swift"
    "$APP_DIR/Editor/CSSStyler.swift"
    "$APP_DIR/Editor/FindBar.swift"
    "$APP_DIR/Languages/LexerRegistry.swift"
    "$APP_DIR/Languages/ColorScheme.swift"
    "$APP_DIR/Languages/TreeSitter/TreeSitter.swift"
    "$APP_DIR/Languages/TreeSitter/TreeSitterManager.swift"
    "$APP_DIR/Languages/TreeSitter/SmartSelection.swift"
    "$APP_DIR/LSP/LSPClient.swift"
    "$APP_DIR/LSP/LSPProtocol.swift"
    "$APP_DIR/LSP/LSPServerRegistry.swift"
    "$APP_DIR/LSP/LSPServerManager.swift"
    "$APP_DIR/LSP/LSPDocumentSync.swift"
    "$APP_DIR/LSP/LSPDiagnostics.swift"
    "$APP_DIR/LSP/LSPHoverPopover.swift"
    "$APP_DIR/LSP/LSPInstaller.swift"
    "$APP_DIR/LSP/LSPDocumentSession.swift"
    "$APP_DIR/LSP/LSPReferencesWindowController.swift"
    "$APP_DIR/LSP/LSPWorkspaceEdit.swift"
    "$APP_DIR/AI/AIService.swift"
    "$APP_DIR/AI/ModelManager.swift"
    "$APP_DIR/AI/GhostText.swift"
    "$APP_DIR/AI/RewriteSheet.swift"
    "$APP_DIR/AI/AIAuxiliaries.swift"
    "$APP_DIR/Notes/WikilinkParser.swift"
    "$APP_DIR/Notes/DailyNotes.swift"
    "$APP_DIR/Notes/TagIndex.swift"
    "$APP_DIR/Notes/Backlinks.swift"
    "$APP_DIR/Notes/ReadingMode.swift"
)

swiftc "${SWIFT_SRCS[@]}" \
    -module-name Sourcepad \
    -target arm64-apple-macos13.0 \
    -import-objc-header "$APP_DIR/Bridge/SciTextView.h" \
    -Xcc -I -Xcc "$TS_ROOT/lib/include" \
    -Xcc -I -Xcc "$TS_ROOT/grammars" \
    -F "$SCI_BUILD" \
    -framework Scintilla \
    -framework AppKit \
    -framework Foundation \
    -framework WebKit \
    -Xlinker "$BUILD_DIR/SciTextView.o" \
    -Xlinker "$BUILD_DIR/KeywordSetsGenerated.o" \
    $(printf -- '-Xlinker %s ' "${TS_OBJS[@]}") \
    -Xlinker -lc++ \
    -Xlinker -lsqlite3 \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -O \
    -o "$BUILD_DIR/Sourcepad"

# 5. Assemble .app bundle
echo "==> Assembling Sourcepad.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources"

mv "$BUILD_DIR/Sourcepad" "$APP_BUNDLE/Contents/MacOS/Sourcepad"
cp -R "$SCI_BUILD/Scintilla.framework" "$APP_BUNDLE/Contents/Frameworks/"
cp "$SCI_BUILD/liblexilla.dylib"      "$APP_BUNDLE/Contents/Frameworks/"
cp "$SCRIPT_DIR/Info.plist.template" "$APP_BUNDLE/Contents/Info.plist"
cp "$APP_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# 6. Codesign (ad-hoc)
echo "==> Codesigning (ad-hoc)"
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | tail -3 || true

# 7. Register with LaunchServices so Finder/Dock pick up the new bundle id + icon.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "Built: $APP_BUNDLE"
echo "Run:   open \"$APP_BUNDLE\""
