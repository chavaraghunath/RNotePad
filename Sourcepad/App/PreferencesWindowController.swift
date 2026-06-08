// SPDX-License-Identifier: MIT
// Sourcepad — single-window preferences UI. Each control writes through to
// `Preferences.shared`, which broadcasts a notification editors observe.

import AppKit

public final class PreferencesWindowController: NSWindowController, NSFontChanging {

    public static let shared: PreferencesWindowController = {
        let vc = PreferencesViewController()
        let window = NSWindow(contentViewController: vc)
        window.styleMask = [.titled, .closable]
        window.title = "Sourcepad Preferences"
        window.setContentSize(NSSize(width: 460, height: 320))
        window.isReleasedWhenClosed = false
        window.center()
        return PreferencesWindowController(window: window)
    }()

    public func showPreferences() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc public func showFromMenu(_ sender: Any?) {
        showPreferences()
    }
}

final class PreferencesViewController: NSViewController {

    private let fontFieldLabel = NSTextField(labelWithString: "Editor font")
    private let fontDisplay    = NSTextField(labelWithString: "")
    private let pickFontButton = NSButton(title: "Choose Font…", target: nil, action: nil)

    private let tabWidthLabel  = NSTextField(labelWithString: "Tab width")
    private let tabWidthStepper = NSStepper()
    private let tabWidthValue  = NSTextField()

    private let lineNumbersToggle = NSButton(checkboxWithTitle: "Show line numbers in the margin",
                                             target: nil, action: nil)
    private let useSpacesToggle   = NSButton(checkboxWithTitle: "Insert spaces when pressing Tab",
                                             target: nil, action: nil)

    private let themeLabel    = NSTextField(labelWithString: "Theme")
    private let themeSegmented = NSSegmentedControl(labels: ["System", "Light", "Dark"],
                                                    trackingMode: .selectOne,
                                                    target: nil, action: nil)

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 320))

        for label in [fontFieldLabel, tabWidthLabel, themeLabel] {
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            label.textColor = .labelColor
        }
        fontDisplay.font = NSFont.systemFont(ofSize: 12)
        fontDisplay.textColor = .secondaryLabelColor
        fontDisplay.isEditable = false
        fontDisplay.isBezeled = false
        fontDisplay.drawsBackground = false

        pickFontButton.target = self
        pickFontButton.action = #selector(pickFont(_:))
        pickFontButton.bezelStyle = .rounded

        tabWidthStepper.minValue = 1
        tabWidthStepper.maxValue = 16
        tabWidthStepper.target = self
        tabWidthStepper.action = #selector(tabStepperChanged(_:))

        tabWidthValue.isEditable = true
        tabWidthValue.isBezeled = true
        tabWidthValue.alignment = .right
        tabWidthValue.target = self
        tabWidthValue.action = #selector(tabValueChanged(_:))
        tabWidthValue.widthAnchor.constraint(equalToConstant: 40).isActive = true

        lineNumbersToggle.target = self
        lineNumbersToggle.action = #selector(toggleLineNumbers(_:))

        useSpacesToggle.target = self
        useSpacesToggle.action = #selector(toggleUseSpaces(_:))

        themeSegmented.target = self
        themeSegmented.action = #selector(themeChanged(_:))

        // Layout via grid.
        let fontRow = NSStackView(views: [fontDisplay, pickFontButton])
        fontRow.orientation = .horizontal
        fontRow.spacing = 8

        let tabRow = NSStackView(views: [tabWidthValue, tabWidthStepper])
        tabRow.orientation = .horizontal
        tabRow.spacing = 4

        let grid = NSGridView(views: [
            [fontFieldLabel, fontRow],
            [tabWidthLabel,  tabRow],
            [themeLabel,     themeSegmented],
            [NSView(),       lineNumbersToggle],
            [NSView(),       useSpacesToggle],
        ])
        grid.columnSpacing = 16
        grid.rowSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])

        self.view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadFromPreferences()
    }

    private func reloadFromPreferences() {
        let p = Preferences.shared
        fontDisplay.stringValue = "\(p.fontName) — \(Int(p.fontSize)) pt"
        tabWidthValue.integerValue = p.tabWidth
        tabWidthStepper.integerValue = p.tabWidth
        lineNumbersToggle.state = p.showLineNumbers ? .on : .off
        useSpacesToggle.state = p.useSpacesForTabs ? .on : .off

        let appearanceOverride = UserDefaults.standard.string(forKey: "Sourcepad.themeOverride")
        switch appearanceOverride {
        case NSAppearance.Name.aqua.rawValue:     themeSegmented.selectedSegment = 1
        case NSAppearance.Name.darkAqua.rawValue: themeSegmented.selectedSegment = 2
        default:                                  themeSegmented.selectedSegment = 0
        }
    }

    // MARK: - Actions

    @objc private func pickFont(_ sender: Any?) {
        let panel = NSFontPanel.shared
        panel.setPanelFont(NSFont(name: Preferences.shared.fontName,
                                  size: Preferences.shared.fontSize) ?? NSFont.systemFont(ofSize: 13),
                           isMultiple: false)
        panel.makeKeyAndOrderFront(nil)
    }

    func changeFont(_ sender: NSFontManager?) {
        guard let sender else { return }
        let current = NSFont(name: Preferences.shared.fontName, size: Preferences.shared.fontSize)
            ?? NSFont.userFixedPitchFont(ofSize: 13)!
        let newFont = sender.convert(current)
        Preferences.shared.fontName = newFont.fontName
        Preferences.shared.fontSize = newFont.pointSize
        fontDisplay.stringValue = "\(newFont.fontName) — \(Int(newFont.pointSize)) pt"
    }

    public func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        return [.face, .collection, .size]
    }

    @objc private func tabStepperChanged(_ sender: NSStepper) {
        Preferences.shared.tabWidth = sender.integerValue
        tabWidthValue.integerValue = sender.integerValue
    }

    @objc private func tabValueChanged(_ sender: NSTextField) {
        let v = max(1, min(16, sender.integerValue))
        Preferences.shared.tabWidth = v
        tabWidthStepper.integerValue = v
        sender.integerValue = v
    }

    @objc private func toggleLineNumbers(_ sender: NSButton) {
        Preferences.shared.showLineNumbers = (sender.state == .on)
    }

    @objc private func toggleUseSpaces(_ sender: NSButton) {
        Preferences.shared.useSpacesForTabs = (sender.state == .on)
    }

    @objc private func themeChanged(_ sender: NSSegmentedControl) {
        let value: String?
        switch sender.selectedSegment {
        case 1: value = NSAppearance.Name.aqua.rawValue
        case 2: value = NSAppearance.Name.darkAqua.rawValue
        default: value = nil
        }
        UserDefaults.standard.set(value, forKey: "Sourcepad.themeOverride")
        if let value, let name = NSAppearance(named: NSAppearance.Name(rawValue: value)) {
            NSApp.appearance = name
        } else {
            NSApp.appearance = nil
        }
    }
}
