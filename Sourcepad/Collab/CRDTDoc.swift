// SPDX-License-Identifier: MIT
// Sourcepad — Phase 32 CRDT live collaboration foundation.
//
// We implement a minimal LSEQ-like document with insert + delete
// operations identified by (sessionID, lamport). Two peers pair via
// Bonjour discovery on the LAN; once connected, every local edit
// broadcasts an op, and remote ops apply through the bridge.
//
// Phase 32 ships the wire model + transport scaffold. The actual
// Bonjour pairing UI + remote-caret rendering land in a follow-on
// pass — the public API here is the surface that pass will plug into.

import Foundation
import Network

public protocol CRDTDelegate: AnyObject {
    func crdt(_ doc: CRDTDoc, remoteOp op: CRDTDoc.Op)
}

public final class CRDTDoc {

    public struct Op: Codable {
        public let session: UUID
        public let lamport: UInt64
        public let kind: Kind
        public let position: UInt64
        public let text: String?
        public let length: UInt64?

        public enum Kind: String, Codable { case insert, delete }
    }

    public let session = UUID()
    public weak var delegate: CRDTDelegate?
    private var clock: UInt64 = 0

    public init() {}

    public func localInsert(at position: Int, text: String) -> Op {
        clock += 1
        return Op(session: session, lamport: clock, kind: .insert,
                  position: UInt64(position), text: text, length: nil)
    }

    public func localDelete(at position: Int, length: Int) -> Op {
        clock += 1
        return Op(session: session, lamport: clock, kind: .delete,
                  position: UInt64(position), text: nil, length: UInt64(length))
    }

    public func receive(_ op: Op) {
        clock = max(clock, op.lamport) + 1
        delegate?.crdt(self, remoteOp: op)
    }
}

public enum CRDTTransport {

    private static var listener: NWListener?

    /// Advertise via Bonjour so a peer Sourcepad on the same network
    /// can discover us. Phase 32 minimum — pairing token + Noise
    /// encryption deferred.
    public static func startAdvertising(port: UInt16 = 0,
                                        onConnection: @escaping (NWConnection) -> Void) {
        let parameters = NWParameters.tcp
        let l = try? NWListener(using: parameters,
                                on: NWEndpoint.Port(rawValue: port) ?? .any)
        l?.service = NWListener.Service(name: "Sourcepad-\(UUID().uuidString.prefix(6))",
                                        type: "_sourcepad._tcp")
        l?.newConnectionHandler = onConnection
        l?.start(queue: .global())
        listener = l
    }

    public static func stop() {
        listener?.cancel()
        listener = nil
    }
}
