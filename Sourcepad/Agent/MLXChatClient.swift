// SPDX-License-Identifier: MIT
// Sourcepad — stream a chat completion from a running mlx_lm.server.
//
// POSTs /v1/chat/completions with stream=true and feeds the incremental bytes to
// MLXSSEParser, emitting content deltas / done / error on the main queue. One
// instance per turn; `cancel()` stops it.

import Foundation

public final class MLXChatStream: NSObject, URLSessionDataDelegate {

    private let onDelta: (String) -> Void
    private let onDone: () -> Void
    private let onError: (String) -> Void

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = ""
    private var finished = false

    public init(onDelta: @escaping (String) -> Void,
                onDone: @escaping () -> Void,
                onError: @escaping (String) -> Void) {
        self.onDelta = onDelta
        self.onDone = onDone
        self.onError = onError
    }

    public func start(baseURL: URL, model: String, prompt: String, maxTokens: Int = 2048) {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        task = s.dataTask(with: req)
        task?.resume()
    }

    public func cancel() {
        task?.cancel()
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer += String(decoding: data, as: UTF8.self)
        let (events, remainder) = MLXSSEParser.parse(buffer: buffer)
        buffer = remainder
        for event in events {
            switch event {
            case .delta(let d): DispatchQueue.main.async { self.onDelta(d) }
            case .done: emitDone()
            case .error(let m): emitError(m)
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            emitError(error.localizedDescription)
        } else {
            // Stream ended (with or without an explicit [DONE]).
            emitDone()
        }
        session.finishTasksAndInvalidate()
    }

    private func emitDone() {
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async { self.onDone() }
    }

    private func emitError(_ message: String) {
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async { self.onError(message) }
    }
}
