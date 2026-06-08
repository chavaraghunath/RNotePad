// SPDX-License-Identifier: MIT
// Sourcepad — user preferences, backed by NSUserDefaults.
//
// Editor panes observe `.sourcepadPreferencesChanged` and re-apply themselves
// whenever any setting changes. Keep the public surface tight — every property
// has a single source of truth in UserDefaults, so reading/writing is cheap.

import AppKit

public extension Notification.Name {
    static let sourcepadPreferencesChanged = Notification.Name("SourcepadPreferencesChanged")
}

public final class Preferences {

    public static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let fontName     = "Sourcepad.editorFontName"
        static let fontSize     = "Sourcepad.editorFontSize"
        static let tabWidth     = "Sourcepad.editorTabWidth"
        static let showLineNumbers = "Sourcepad.showLineNumbers"
        static let useSpaces    = "Sourcepad.useSpacesForTabs"
        static let wordWrap     = "Sourcepad.wordWrap"
        static let zoomLevel    = "Sourcepad.zoomLevel"
        static let indentGuides = "Sourcepad.indentGuides"
        static let showInvisibles = "Sourcepad.showInvisibles"
        static let showEOL      = "Sourcepad.showEOL"
        static let trimOnSave   = "Sourcepad.trimTrailingWhitespaceOnSave"
    }

    private init() {
        defaults.register(defaults: [
            Key.fontName: "Menlo",
            Key.fontSize: 13,
            Key.tabWidth: 4,
            Key.showLineNumbers: true,
            Key.useSpaces: true,
            Key.wordWrap: false,
            Key.zoomLevel: 0,
            Key.indentGuides: true,
            Key.showInvisibles: false,
            Key.showEOL: false,
            Key.trimOnSave: false,
        ])
    }

    public var fontName: String {
        get { defaults.string(forKey: Key.fontName) ?? "Menlo" }
        set { defaults.set(newValue, forKey: Key.fontName); notify() }
    }

    public var fontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.fontSize)) }
        set { defaults.set(Double(newValue), forKey: Key.fontSize); notify() }
    }

    public var tabWidth: Int {
        get { max(1, defaults.integer(forKey: Key.tabWidth)) }
        set { defaults.set(max(1, newValue), forKey: Key.tabWidth); notify() }
    }

    public var showLineNumbers: Bool {
        get { defaults.bool(forKey: Key.showLineNumbers) }
        set { defaults.set(newValue, forKey: Key.showLineNumbers); notify() }
    }

    public var useSpacesForTabs: Bool {
        get { defaults.bool(forKey: Key.useSpaces) }
        set { defaults.set(newValue, forKey: Key.useSpaces); notify() }
    }

    public var wordWrap: Bool {
        get { defaults.bool(forKey: Key.wordWrap) }
        set { defaults.set(newValue, forKey: Key.wordWrap); notify() }
    }

    public var zoomLevel: Int {
        get { defaults.integer(forKey: Key.zoomLevel) }
        set { defaults.set(max(-10, min(50, newValue)), forKey: Key.zoomLevel); notify() }
    }

    public var indentGuides: Bool {
        get { defaults.bool(forKey: Key.indentGuides) }
        set { defaults.set(newValue, forKey: Key.indentGuides); notify() }
    }

    public var showInvisibles: Bool {
        get { defaults.bool(forKey: Key.showInvisibles) }
        set { defaults.set(newValue, forKey: Key.showInvisibles); notify() }
    }

    public var showEOL: Bool {
        get { defaults.bool(forKey: Key.showEOL) }
        set { defaults.set(newValue, forKey: Key.showEOL); notify() }
    }

    public var trimTrailingWhitespaceOnSave: Bool {
        get { defaults.bool(forKey: Key.trimOnSave) }
        set { defaults.set(newValue, forKey: Key.trimOnSave); notify() }
    }

    public enum ExternalChangeBehavior: String {
        case prompt, autoReload, ignore
    }

    public var externalChangeBehavior: ExternalChangeBehavior {
        get {
            let raw = defaults.string(forKey: "Sourcepad.externalChangeBehavior") ?? "prompt"
            return ExternalChangeBehavior(rawValue: raw) ?? .prompt
        }
        set { defaults.set(newValue.rawValue, forKey: "Sourcepad.externalChangeBehavior"); notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: .sourcepadPreferencesChanged, object: self)
    }
}
