# Vendored: SwiftTerm

Source: https://github.com/migueldeicaza/SwiftTerm
Commit: a3b8c9b680cb38d87d2a067b8ecd6427910538a6
License: MIT (see LICENSE)
Vendored: 2026-06-14

## What was included
- All of Sources/SwiftTerm/*.swift (core), Apple/ (incl. Metal), Mac/
- Excluded: iOS/, Documentation.docc/, Apple/Metal/Shaders.metal (we use the
  default CoreText renderer; the Metal GPU path is disabled by default and
  never enabled by Sourcepad, so the shader resource is not needed).

## Local patches (keep minimal; re-apply on upgrade)
1. MetalTerminalRenderer.swift: `Bundle.module` -> `Bundle(for: MetalTerminalRenderer.self)`
   The flat swiftc build has no SwiftPM resource bundle. This line only runs
   if the Metal renderer is activated, which Sourcepad never does.

## Build integration
- All .swift files added to SWIFT_SRCS in Sourcepad/Build/build.sh.
- Compiled into the single app module (no `import SwiftTerm`).
- Extra frameworks linked: CoreText, QuartzCore, Carbon, MetalKit, Metal, ImageIO.
