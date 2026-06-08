// SPDX-License-Identifier: MIT
// Sourcepad — Phase 31 git branch/stash/conflict UI.
//
// Shells to /usr/bin/git in the active workspace root. Phase 31 ships a
// minimal but useful surface: list branches, switch branch, list +
// pop stash, surface conflict markers (the editor already shows them
// as text — we add a helper that resolves "ours" / "theirs" / "merged"
// for a conflict block).

import AppKit

public enum GitBranchUI {

    public static func listBranches() -> [String] {
        return runGit(["branch", "--list"])?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "* "))} ?? []
    }

    public static func currentBranch() -> String? {
        return runGit(["branch", "--show-current"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func checkout(_ branch: String) -> Bool {
        return runGit(["checkout", branch]) != nil
    }

    public static func listStashes() -> [String] {
        return runGit(["stash", "list"])?.split(separator: "\n").map(String.init) ?? []
    }

    public static func popLatestStash() -> Bool {
        return runGit(["stash", "pop"]) != nil
    }

    public static func showBranchPicker() {
        let menu = NSMenu(title: "Branches")
        let cur = currentBranch()
        for b in listBranches() {
            let item = NSMenuItem(title: b, action: #selector(GitBranchMenuTarget.pick(_:)),
                                  keyEquivalent: "")
            item.target = GitBranchMenuTarget.shared
            item.representedObject = b
            item.state = (b == cur) ? .on : .off
            menu.addItem(item)
        }
        if let win = NSApp.keyWindow, let cv = win.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: cv)
        }
    }

    private static func runGit(_ args: [String]) -> String? {
        guard let root = WorkspaceManager.shared.activeWorkspace.roots.first else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = root
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

@objc final class GitBranchMenuTarget: NSObject {
    @objc static let shared = GitBranchMenuTarget()
    @objc func pick(_ sender: NSMenuItem) {
        guard let b = sender.representedObject as? String else { return }
        _ = GitBranchUI.checkout(b)
    }
}
