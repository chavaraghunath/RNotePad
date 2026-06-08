// SPDX-License-Identifier: MIT
// Sourcepad — Phase 24 macOS speech synthesis for the current selection.

import AppKit
import AVFoundation

public enum SpeakSelection {

    private static let synth = AVSpeechSynthesizer()

    public static func speakActiveSelection() {
        guard let doc = NSDocumentController.shared.currentDocument as? TextDocument,
              let pane = doc.primaryEditorViewController()?.editorPane else {
            NSSound.beep(); return
        }
        let sel = SciGetSelectionBytes(pane.view)
        let text: String
        if sel.length > 0 {
            let allBytes = Array(SciGetText(pane.view).utf8)
            guard sel.location + sel.length <= allBytes.count else { return }
            text = String(decoding: allBytes[sel.location..<sel.location+sel.length], as: UTF8.self)
        } else {
            text = SciGetText(pane.view)
        }
        guard !text.isEmpty else { NSSound.beep(); return }
        synth.stopSpeaking(at: .immediate)
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: nil)
        synth.speak(utt)
    }

    public static func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}
