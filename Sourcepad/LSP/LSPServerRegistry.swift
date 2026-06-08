// SPDX-License-Identifier: MIT
// Sourcepad — known language-server adapters.
//
// For each language we support, this registry knows:
//   - the LSP identifier (the languageId in didOpen messages)
//   - which executable to spawn, with what args
//   - where to look for the binary in common toolchain locations
//   - how to instruct the user to install it (Phase 7 uses this for the
//     in-app "Install pyright?" prompt; for now we just surface the install
//     command in the menu's tooltip).

import Foundation

public struct LSPServerSpec {

    /// LSP languageId — what we send in didOpen messages.
    public let languageId: String

    /// Sourcepad's internal lexer name (Lexilla identifier). Multiple
    /// Lexilla lexers can map to the same languageId (e.g. javascript +
    /// typescript both use "javascript" lexer in Sourcepad today but
    /// distinct LSP languageIds).
    public let lexerName: String

    /// Display name for menus / status bar.
    public let displayName: String

    /// Executable name (resolved against PATH + commonPaths).
    public let executableName: String

    /// Command-line args for stdio mode.
    public let arguments: [String]

    /// Extra paths to look for the executable when PATH doesn't have it.
    public let commonPaths: [String]

    /// Human-readable install command to surface if not found.
    public let installHint: String

    public init(languageId: String,
                lexerName: String,
                displayName: String,
                executableName: String,
                arguments: [String],
                commonPaths: [String] = [],
                installHint: String) {
        self.languageId = languageId
        self.lexerName = lexerName
        self.displayName = displayName
        self.executableName = executableName
        self.arguments = arguments
        self.commonPaths = commonPaths
        self.installHint = installHint
    }

    /// Resolve the executable. Returns nil if not found.
    public func locate() -> URL? {
        // 1. PATH lookup via `which`.
        if let url = LSPServerSpec.which(executableName) {
            return url
        }
        // 2. Common toolchain locations.
        for candidate in commonPaths {
            let url = URL(fileURLWithPath: candidate)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// `which <name>` resolution. Returns nil if absent or empty.
    static func which(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}

public enum LSPServerRegistry {

    /// All known servers. Phase 6 ships Pyright as the proof language;
    /// Phase 7 grows this list to 9 servers.
    public static let all: [LSPServerSpec] = [
        LSPServerSpec(
            languageId: "python",
            lexerName: "python",
            displayName: "Pyright (Python)",
            executableName: "pyright-langserver",
            arguments: ["--stdio"],
            commonPaths: [
                "/opt/homebrew/bin/pyright-langserver",
                "/usr/local/bin/pyright-langserver",
            ],
            installHint: "npm install -g pyright"),
    ]

    /// Lookup by Sourcepad lexer name.
    public static func spec(forLexer lexer: String) -> LSPServerSpec? {
        return all.first { $0.lexerName == lexer }
    }
}
