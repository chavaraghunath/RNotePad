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
    }

    private init() {
        defaults.register(defaults: [
            Key.fontName: "Menlo",
            Key.fontSize: 13,
            Key.tabWidth: 4,
            Key.showLineNumbers: true,
            Key.useSpaces: true,
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

    private func notify() {
        NotificationCenter.default.post(name: .sourcepadPreferencesChanged, object: self)
    }
}
