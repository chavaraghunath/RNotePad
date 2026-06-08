// SPDX-License-Identifier: MIT
// Sourcepad — known local-AI models + first-run picker.
//
// Each entry is a HuggingFace model ID that mlx-lm can fetch and run.
// First launch (or when AI is first enabled) shows a picker. Models
// download lazily — the first request to a fresh model takes longer
// while mlx-lm pulls the weights.

import AppKit

public struct AIModel {
    public let id: String          // HuggingFace ID (mlx-community/...)
    public let displayName: String
    public let sizeGB: Int
    public let isCoder: Bool

    public init(id: String, displayName: String, sizeGB: Int, isCoder: Bool) {
        self.id = id
        self.displayName = displayName
        self.sizeGB = sizeGB
        self.isCoder = isCoder
    }
}

public enum ModelManager {

    public static let known: [AIModel] = [
        AIModel(id: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
                displayName: "Qwen2.5 Coder 3B (4-bit)",
                sizeGB: 2, isCoder: true),
        AIModel(id: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
                displayName: "Qwen2.5 Coder 7B (4-bit)",
                sizeGB: 5, isCoder: true),
        AIModel(id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                displayName: "Llama 3.2 3B (4-bit)",
                sizeGB: 2, isCoder: false),
        AIModel(id: "mlx-community/DeepSeek-Coder-V2-Lite-Instruct-4bit-mlx",
                displayName: "DeepSeek Coder V2 Lite (4-bit)",
                sizeGB: 9, isCoder: true),
    ]

    /// Show a model picker the first time AI is enabled. Returns the
    /// picked model id (already persisted to Preferences) or nil if
    /// the user cancelled.
    @discardableResult
    public static func promptToPickModel(parent: NSWindow?) -> String? {
        let alert = NSAlert()
        alert.messageText = "Pick a local AI model"
        alert.informativeText = "Sourcepad's AI features run entirely on-device via MLX. Picking a coder model is recommended for ghost-text / Cmd-K rewrite."

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        for m in known {
            popup.addItem(withTitle: "\(m.displayName)  — ~\(m.sizeGB) GB")
            popup.lastItem?.representedObject = m.id
        }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Use This Model")
        alert.addButton(withTitle: "Cancel")
        let response: NSApplication.ModalResponse
        if let parent {
            // beginSheetModal + completion isn't synchronous, so run modally
            // anchored to the app (the user opted in via menu item).
            response = alert.runModal()
            _ = parent
        } else {
            response = alert.runModal()
        }
        guard response == .alertFirstButtonReturn else { return nil }
        guard let id = popup.selectedItem?.representedObject as? String else { return nil }
        Preferences.shared.aiModelID = id
        Preferences.shared.aiEnabled = true
        return id
    }
}
