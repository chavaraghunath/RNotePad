// SPDX-License-Identifier: MIT
// Sourcepad — watches an on-disk file for external mutations and notifies
// when the buffer should be reloaded. Wraps DispatchSource's VNODE watcher.

import Foundation

public final class ExternalChangeWatcher {

    public enum Event {
        case modified
        case removed       // delete OR rename of the watched path
    }

    public typealias Handler = (Event) -> Void

    private let url: URL
    private let handler: Handler
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.15

    /// Set true around save() flows to suppress the inevitable self-write.
    public var isPerformingSave: Bool = false

    public init(url: URL, handler: @escaping Handler) {
        self.url = url
        self.handler = handler
    }

    public func start() {
        stop()  // idempotent
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.fd = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: .global())
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let mask = src.data
            if self.isPerformingSave { return }
            DispatchQueue.main.async {
                if mask.contains(.delete) || mask.contains(.rename) {
                    self.handler(.removed)
                } else {
                    self.scheduleDebounced { self.handler(.modified) }
                }
            }
        }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        self.source = src
    }

    public func stop() {
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
        fd = -1  // close happens in cancel handler
    }

    deinit { stop() }

    private func scheduleDebounced(_ block: @escaping () -> Void) {
        debounce?.cancel()
        let work = DispatchWorkItem(block: block)
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
