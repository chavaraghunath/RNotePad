// SPDX-License-Identifier: MIT
// Sourcepad — detect the package managers used to install agent CLIs.
//
// The "Agent CLIs" pane shows a prerequisites strip (Homebrew · Node · Python)
// and only offers install methods whose package manager is actually present.
// Detection reuses `AgentExecutable.locate`, which probes a realistic PATH plus
// the usual Homebrew/asdf/volta/cargo locations a Finder-launched app misses.
//
// Foundation-only and side-effect-free (locating an executable does not run it).

import Foundation

public enum PackageManagers {

    public struct Tool: Equatable {
        public let command: String     // "brew", "npm", "pipx"
        public let label: String       // "Homebrew", "Node (npm)", "Python (pipx)"
        public let installHintURL: String  // where to get it if missing
    }

    /// Managers Sourcepad knows how to drive, in the order shown in the strip.
    public static let known: [Tool] = [
        Tool(command: "brew", label: "Homebrew", installHintURL: "https://brew.sh"),
        Tool(command: "npm",  label: "Node (npm)", installHintURL: "https://nodejs.org"),
        Tool(command: "pipx", label: "Python (pipx)", installHintURL: "https://pipx.pypa.io"),
    ]

    /// True when `command` resolves to an executable on the enriched PATH.
    public static func isAvailable(_ command: String) -> Bool {
        AgentExecutable.locate(command) != nil
    }

    /// Snapshot of which known managers are present — for the prereq strip.
    public static func status() -> [(tool: Tool, available: Bool)] {
        known.map { ($0, isAvailable($0.command)) }
    }
}
