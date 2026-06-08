// SPDX-License-Identifier: MIT
// Sourcepad — known language-server adapters.
//
// Keying note: an LSPServerSpec is matched by file extension, NOT by the
// Lexilla lexer name. Multiple languages share Lexilla lexers (e.g.
// Sourcepad uses the "cpp" lexer for JS/TS/Go) but each has a distinct
// LSP server. Extension keying gives one-to-one routing without coupling
// LSP identity to highlighting choice.

import Foundation

public struct LSPServerSpec {

    /// LSP languageId — what we send in didOpen messages.
    public let languageId: String

    /// Display name for menus / status bar.
    public let displayName: String

    /// File extensions (no dot, lowercased) that activate this server.
    public let fileExtensions: [String]

    /// Executable name (resolved against PATH + commonPaths).
    public let executableName: String

    /// Command-line args for stdio mode.
    public let arguments: [String]

    /// Extra paths to look for the executable when PATH doesn't have it.
    public let commonPaths: [String]

    /// Human-readable install command to surface if not found.
    public let installHint: String

    public init(languageId: String,
                displayName: String,
                fileExtensions: [String],
                executableName: String,
                arguments: [String],
                commonPaths: [String] = [],
                installHint: String) {
        self.languageId = languageId
        self.displayName = displayName
        self.fileExtensions = fileExtensions
        self.executableName = executableName
        self.arguments = arguments
        self.commonPaths = commonPaths
        self.installHint = installHint
    }

    /// Resolve the executable. Returns nil if not found.
    public func locate() -> URL? {
        if let url = LSPServerSpec.which(executableName) { return url }
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

    /// All known servers. Lookup is O(N · M) where N=specs, M=extensions
    /// per spec — fine at the current scale.
    public static let all: [LSPServerSpec] = [
        // --- Python -----------------------------------------------------
        LSPServerSpec(
            languageId: "python",
            displayName: "Pyright (Python)",
            fileExtensions: ["py", "pyi", "pyw"],
            executableName: "pyright-langserver",
            arguments: ["--stdio"],
            commonPaths: [
                "/opt/homebrew/bin/pyright-langserver",
                "/usr/local/bin/pyright-langserver",
            ],
            installHint: "npm install -g pyright"),

        // --- Go ---------------------------------------------------------
        LSPServerSpec(
            languageId: "go",
            displayName: "gopls (Go)",
            fileExtensions: ["go"],
            executableName: "gopls",
            arguments: [],
            commonPaths: [
                "/opt/homebrew/bin/gopls",
                "/usr/local/bin/gopls",
                "\(NSHomeDirectory())/go/bin/gopls",
            ],
            installHint: "go install golang.org/x/tools/gopls@latest"),

        // --- Rust -------------------------------------------------------
        LSPServerSpec(
            languageId: "rust",
            displayName: "rust-analyzer",
            fileExtensions: ["rs"],
            executableName: "rust-analyzer",
            arguments: [],
            commonPaths: [
                "/opt/homebrew/bin/rust-analyzer",
                "/usr/local/bin/rust-analyzer",
                "\(NSHomeDirectory())/.cargo/bin/rust-analyzer",
            ],
            installHint: "rustup component add rust-analyzer"),

        // --- TypeScript / JavaScript -----------------------------------
        LSPServerSpec(
            languageId: "typescript",
            displayName: "TypeScript Language Server",
            fileExtensions: ["ts", "tsx", "js", "jsx", "mjs", "cjs"],
            executableName: "typescript-language-server",
            arguments: ["--stdio"],
            commonPaths: [
                "/opt/homebrew/bin/typescript-language-server",
                "/usr/local/bin/typescript-language-server",
            ],
            installHint: "npm install -g typescript typescript-language-server"),

        // --- C / C++ / Obj-C / Obj-C++ ---------------------------------
        LSPServerSpec(
            languageId: "cpp",
            displayName: "clangd (C/C++/ObjC)",
            fileExtensions: ["c", "cc", "cxx", "cpp", "h", "hh", "hpp", "hxx",
                             "m", "mm", "objc", "objcpp"],
            executableName: "clangd",
            arguments: [],
            commonPaths: [
                "/opt/homebrew/opt/llvm/bin/clangd",
                "/usr/local/opt/llvm/bin/clangd",
                "/Library/Developer/CommandLineTools/usr/bin/clangd",
                "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clangd",
            ],
            installHint: "brew install llvm   (or use the Xcode-bundled clangd)"),

        // --- Ruby -------------------------------------------------------
        LSPServerSpec(
            languageId: "ruby",
            displayName: "ruby-lsp",
            fileExtensions: ["rb", "rbw"],
            executableName: "ruby-lsp",
            arguments: [],
            commonPaths: [
                "/opt/homebrew/lib/ruby/gems/3.4.0/bin/ruby-lsp",
            ],
            installHint: "gem install ruby-lsp"),

        // --- Lua --------------------------------------------------------
        LSPServerSpec(
            languageId: "lua",
            displayName: "lua-language-server",
            fileExtensions: ["lua"],
            executableName: "lua-language-server",
            arguments: [],
            commonPaths: [
                "/opt/homebrew/bin/lua-language-server",
            ],
            installHint: "brew install lua-language-server"),

        // --- Bash -------------------------------------------------------
        LSPServerSpec(
            languageId: "shellscript",
            displayName: "bash-language-server",
            fileExtensions: ["sh", "bash", "zsh", "ksh"],
            executableName: "bash-language-server",
            arguments: ["start"],
            commonPaths: [
                "/opt/homebrew/bin/bash-language-server",
            ],
            installHint: "npm install -g bash-language-server"),

        // --- HTML / CSS / JSON / YAML (single binary via vscode-langservers-extracted) --
        LSPServerSpec(
            languageId: "html",
            displayName: "HTML Language Server (vscode-langservers-extracted)",
            fileExtensions: ["html", "htm", "xhtml"],
            executableName: "vscode-html-language-server",
            arguments: ["--stdio"],
            commonPaths: ["/opt/homebrew/bin/vscode-html-language-server"],
            installHint: "npm install -g vscode-langservers-extracted"),

        LSPServerSpec(
            languageId: "css",
            displayName: "CSS Language Server",
            fileExtensions: ["css", "scss", "less"],
            executableName: "vscode-css-language-server",
            arguments: ["--stdio"],
            commonPaths: ["/opt/homebrew/bin/vscode-css-language-server"],
            installHint: "npm install -g vscode-langservers-extracted"),

        LSPServerSpec(
            languageId: "json",
            displayName: "JSON Language Server",
            fileExtensions: ["json", "jsonc"],
            executableName: "vscode-json-language-server",
            arguments: ["--stdio"],
            commonPaths: ["/opt/homebrew/bin/vscode-json-language-server"],
            installHint: "npm install -g vscode-langservers-extracted"),

        // YAML LSP is a separate package even though the others above
        // come bundled — install hint kept consistent for npm path.
        LSPServerSpec(
            languageId: "yaml",
            displayName: "yaml-language-server",
            fileExtensions: ["yaml", "yml"],
            executableName: "yaml-language-server",
            arguments: ["--stdio"],
            commonPaths: ["/opt/homebrew/bin/yaml-language-server"],
            installHint: "npm install -g yaml-language-server"),
    ]

    /// Lookup by file extension (case-insensitive, no leading dot).
    public static func spec(forExtension ext: String) -> LSPServerSpec? {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return all.first { $0.fileExtensions.contains(normalized) }
    }

    /// Lookup by file URL.
    public static func spec(for url: URL) -> LSPServerSpec? {
        return spec(forExtension: url.pathExtension)
    }
}
