// SPDX-License-Identifier: MIT
// Sourcepad — detect how to verify a workspace (the "Verify" in Plan→Act→Verify).
//
// After the agent edits code, Sourcepad runs the project's own build/test/lint so
// the change is proven, not just produced. This picks a verification plan from the
// workspace's manifest files (package.json, Cargo.toml, go.mod, …). Pure +
// Foundation-only so it's exhaustively headless-testable.

import Foundation

public struct VerifyPlan: Equatable {
    public struct Step: Equatable {
        public let label: String     // "Build", "Test", "Lint"
        public let command: String   // shell command, run via the user's shell
        public init(label: String, command: String) { self.label = label; self.command = command }
    }
    public let ecosystem: String     // "npm", "cargo", … (for display); "" if none
    public let steps: [Step]
    public init(ecosystem: String, steps: [Step]) { self.ecosystem = ecosystem; self.steps = steps }
    public var isEmpty: Bool { steps.isEmpty }
}

public enum VerifyDetector {

    public static func detect(workspaceRoot root: String) -> VerifyPlan {
        let fm = FileManager.default
        func path(_ p: String) -> String { (root as NSString).appendingPathComponent(p) }
        func exists(_ p: String) -> Bool { fm.fileExists(atPath: path(p)) }
        func read(_ p: String) -> String? { try? String(contentsOfFile: path(p), encoding: .utf8) }

        // — Node / JavaScript / TypeScript —
        if let pkg = read("package.json") {
            let pm = exists("pnpm-lock.yaml") ? "pnpm"
                   : exists("yarn.lock") ? "yarn"
                   : exists("bun.lockb") ? "bun" : "npm"
            let scripts = jsonScriptNames(pkg)
            var steps: [VerifyPlan.Step] = []
            if scripts.contains("build") { steps.append(.init(label: "Build", command: runScript(pm, "build"))) }
            if scripts.contains("test")  { steps.append(.init(label: "Test",  command: runScript(pm, "test"))) }
            if scripts.contains("lint")  { steps.append(.init(label: "Lint",  command: runScript(pm, "lint"))) }
            if !steps.isEmpty { return VerifyPlan(ecosystem: pm, steps: steps) }
        }

        // — Rust —
        if exists("Cargo.toml") {
            return VerifyPlan(ecosystem: "cargo", steps: [
                .init(label: "Build", command: "cargo build"),
                .init(label: "Test",  command: "cargo test"),
            ])
        }

        // — Go —
        if exists("go.mod") {
            return VerifyPlan(ecosystem: "go", steps: [
                .init(label: "Build", command: "go build ./..."),
                .init(label: "Test",  command: "go test ./..."),
            ])
        }

        // — Swift package —
        if exists("Package.swift") {
            return VerifyPlan(ecosystem: "swift", steps: [
                .init(label: "Build", command: "swift build"),
                .init(label: "Test",  command: "swift test"),
            ])
        }

        // — Python —
        if exists("pyproject.toml") || exists("pytest.ini") || exists("setup.py") || exists("tox.ini") {
            return VerifyPlan(ecosystem: "python", steps: [
                .init(label: "Test", command: "python -m pytest -q"),
            ])
        }

        // — Make —
        if let mk = read("Makefile") {
            var steps: [VerifyPlan.Step] = []
            if hasMakeTarget(mk, "build") { steps.append(.init(label: "Build", command: "make build")) }
            if hasMakeTarget(mk, "test")  { steps.append(.init(label: "Test",  command: "make test")) }
            if hasMakeTarget(mk, "lint")  { steps.append(.init(label: "Lint",  command: "make lint")) }
            if !steps.isEmpty { return VerifyPlan(ecosystem: "make", steps: steps) }
        }

        // — JVM —
        if exists("pom.xml") {
            return VerifyPlan(ecosystem: "maven", steps: [.init(label: "Test", command: "mvn -q test")])
        }
        if exists("build.gradle") || exists("build.gradle.kts") {
            let g = exists("gradlew") ? "./gradlew" : "gradle"
            return VerifyPlan(ecosystem: "gradle", steps: [.init(label: "Test", command: "\(g) test")])
        }

        return VerifyPlan(ecosystem: "", steps: [])
    }

    // MARK: - Helpers

    /// Names of scripts defined in a package.json's "scripts" object.
    static func jsonScriptNames(_ packageJSON: String) -> Set<String> {
        guard let data = packageJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = obj["scripts"] as? [String: Any] else { return [] }
        return Set(scripts.keys)
    }

    /// Shell command to run a named package script for a package manager.
    static func runScript(_ pm: String, _ name: String) -> String {
        switch pm {
        case "yarn": return "yarn \(name)"
        case "bun":  return "bun run \(name)"
        default:     return "\(pm) run \(name)"   // npm / pnpm
        }
    }

    /// Whether a Makefile declares a `<target>:` rule.
    static func hasMakeTarget(_ makefile: String, _ target: String) -> Bool {
        let pattern = "(?m)^\(NSRegularExpression.escapedPattern(for: target))[ \\t]*:"
        return makefile.range(of: pattern, options: .regularExpression) != nil
    }
}
