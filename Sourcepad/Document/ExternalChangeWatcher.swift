// SPDX-License-Identifier: MIT
// Sourcepad — watches an on-disk file for external mutations and notifies
// when the buffer should be reloaded. Wraps DispatchSource's VNODE watcher.
//
// Why the event mask is narrow:
//   We deliberately do NOT subscribe to `.attrib`. macOS fires `.attrib`
//   constantly for metadata churn that the user never made:
//     - Spotlight (mds / mdworker) touching xattrs while indexing
//     - Time Machine local snapshots
//     - Finder updating com.apple.metadata:kMDItemLastUsedDate xattrs
//     - Quick Look generators stamping previews
//     - iCloud / Dropbox / Backblaze / Arq sync agents
//     - Antivirus / EDR scanners
//   None of these change file CONTENT, but they all flip `.attrib`. If we
//   prompt on them the user sees "File changed on disk" pop up
//   continuously while the file just sits there.
//
// Defensive mtime+size gate:
//   Even .write / .extend can fire when no actual content change occurred
//   (touch(1), copyfile reflinks, etc.). Before notifying, we compare the
//   file's current modificationDate + size against the values we snapped
//   at start (or after the most recent self-save). If neither changed, we
//   silently swallow the event.

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

    /// Last-known disk state. Used to suppress spurious VNODE events
    /// where mtime + size haven't actually changed (touch / metadata
    /// rewrites / sync agents). Updated on start() and refreshSnapshot().
    private var lastMTime: TimeInterval = 0
    private var lastSize: Int64 = 0

    /// Set true around save() flows to suppress the inevitable self-write.
    /// TextDocument.write(to:ofType:) releases this 0.5s after super.write
    /// returns so the in-flight VNODE notification has time to arrive.
    public var isPerformingSave: Bool = false {
        didSet {
            // When the save sequence ends, refresh the snapshot so a
            // future VNODE event compares against the *new* on-disk
            // mtime — not the pre-save one.
            if oldValue == true && isPerformingSave == false {
                refreshSnapshot()
            }
        }
    }

    public init(url: URL, handler: @escaping Handler) {
        self.url = url
        self.handler = handler
    }

    public func start() {
        stop()  // idempotent
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.fd = fd
        refreshSnapshot()

        // Deliberately narrow: only content-mutation events. See file
        // header for the reasoning on excluding .attrib.
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .global())
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let mask = src.data
            if self.isPerformingSave { return }
            DispatchQueue.main.async {
                if mask.contains(.delete) || mask.contains(.rename) {
                    self.handler(.removed)
                } else if self.diskActuallyChanged() {
                    self.scheduleDebounced { self.handler(.modified) }
                }
                // Otherwise: VNODE fired but mtime+size unchanged → no-op.
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

    // MARK: - Disk-state snapshot

    /// Re-read the file's mtime + size and store them as the new baseline.
    /// Called after we own a write (save just completed) so subsequent
    /// VNODE events compare against the right reference.
    public func refreshSnapshot() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return
        }
        if let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 {
            lastMTime = mtime
        }
        if let size = (attrs[.size] as? NSNumber)?.int64Value {
            lastSize = size
        }
    }

    /// True if mtime OR size differs from what we last recorded — i.e.
    /// the file's content (or at least the part the kernel tracks) really
    /// changed since we cared. Tolerates ~10ms mtime jitter so kernels
    /// that round timestamps don't false-positive.
    private func diskActuallyChanged() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            // File vanished out from under us — treat as a real change.
            return true
        }
        let curMTime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let curSize  = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtimeChanged = abs(curMTime - lastMTime) > 0.01
        let sizeChanged  = curSize != lastSize
        if mtimeChanged || sizeChanged {
            // Update baseline so the next event compares against this state.
            lastMTime = curMTime
            lastSize = curSize
            return true
        }
        return false
    }
}
