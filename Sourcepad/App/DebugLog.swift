// SPDX-License-Identifier: MIT
// Sourcepad — file-based logger so we can debug regardless of stderr routing.
// Writes to /tmp/sourcepad.log. Each line is timestamped. Append mode.

import Foundation

enum DebugLog {
    static let path = "/tmp/sourcepad.log"

    static func log(_ message: String, file: String = #file, line: Int = #line) {
        // Respect the privacy setting (Settings ▸ Privacy). Default on.
        guard UserDefaults.standard.object(forKey: "Sourcepad.debugLoggingEnabled") as? Bool ?? true else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        let file = (file as NSString).lastPathComponent
        let entry = "\(ts) \(file):\(line)  \(message)\n"
        if let data = entry.data(using: .utf8) {
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
        NSLog("%@", entry)
    }
}
