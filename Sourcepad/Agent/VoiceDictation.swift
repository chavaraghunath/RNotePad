// SPDX-License-Identifier: MIT
// Sourcepad — voice dictation for the agent chat input.
//
// `VoiceDictation` is the backend seam: the default `AppleSpeechDictation` uses
// SFSpeechRecognizer (on-device when supported) for real-time streaming, native,
// download-free dictation. A future MLX-Whisper backend can conform to the same
// protocol without touching the UI.

import Foundation
import Speech
import AVFoundation

public protocol VoiceDictation: AnyObject {
    var isRunning: Bool { get }
    /// Begin dictation. `onText` fires (main queue) with the cumulative
    /// transcription so far as the user speaks; `onError` on failure.
    func start(onText: @escaping (String) -> Void, onError: @escaping (String) -> Void)
    func stop()
}

public final class AppleSpeechDictation: VoiceDictation {

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    public private(set) var isRunning = false

    public init() {}

    /// Request speech + microphone permission; completion(true) when both granted.
    public static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            let speechOK = (speechStatus == .authorized)
            AVCaptureDevice.requestAccess(for: .audio) { micOK in
                DispatchQueue.main.async { completion(speechOK && micOK) }
            }
        }
    }

    public func start(onText: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        guard !isRunning else { return }
        guard let recognizer, recognizer.isAvailable else {
            onError("Speech recognition is unavailable for your locale."); return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cleanup()
            onError("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }
        isRunning = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { onText(text) }
            }
            if let error {
                DispatchQueue.main.async { onError(error.localizedDescription) }
                self?.stop()
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        cleanup()
    }

    private func cleanup() {
        request = nil
        task = nil
        isRunning = false
    }
}
