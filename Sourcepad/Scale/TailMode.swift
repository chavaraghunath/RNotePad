// SPDX-License-Identifier: MIT
// Sourcepad — Phase 30 tail mode.
//
// Follows file appends like `tail -f`. Polls the file's size every
// 250ms; when it grows, reads the new bytes and appends to the editor
// buffer (via the bridge's new Insert-at-end path).

import AppKit

public final class TailMode {

    public static let shared = TailMode()

    private var watchers: [URL: DispatchSourceTimer] = [:]

    public func startFollowing(_ url: URL,
                               pane: EditorPaneViewController) {
        stopFollowing(url)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        var lastSize: UInt64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let sz = attrs[.size] as? NSNumber {
            lastSize = sz.uint64Value
        }
        timer.setEventHandler { [weak pane] in
            guard let pane else { return }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let sz = attrs[.size] as? NSNumber,
                  sz.uint64Value > lastSize else { return }
            let delta = sz.uint64Value - lastSize
            lastSize = sz.uint64Value
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? handle.close() }
            try? handle.seek(toOffset: sz.uint64Value - delta)
            let newBytes = handle.readData(ofLength: Int(delta))
            guard let str = String(data: newBytes, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                let end = SciTextLengthBytes(pane.view)
                SciInsertTextAt(pane.view, end, str)
                SciSetSelectionBytes(pane.view, end + str.lengthOfBytes(using: .utf8),
                                     end + str.lengthOfBytes(using: .utf8))
            }
        }
        timer.resume()
        watchers[url] = timer
    }

    public func stopFollowing(_ url: URL) {
        watchers[url]?.cancel()
        watchers.removeValue(forKey: url)
    }
}
