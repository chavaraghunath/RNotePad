// SPDX-License-Identifier: MIT
// Sourcepad — SQLite-backed persistence for agent conversations.
//
// One database at
//   ~/Library/Application Support/Sourcepad/agent.db
//
// Schema:
//   conversation         (id, title, created_at, updated_at, current_cli, current_model, cwd)
//   conversation_session (conversation_id → conversation, cli, native_session_id;
//                         UNIQUE(conversation_id, cli))  — per-CLI resume ids
//   message              (id, conversation_id → conversation, role, content, kind, created_at)
//   tool_call            (id, message_id → message, kind, title, detail, status)
//   conversation_vec     (conversation_id → conversation, dims, embed_model, embedding BLOB)
//
// Mirrors Workspace/ProjectIndex.swift: one serial queue, one connection, raw
// SQLite C API (system -lsqlite3, no vendored amalgamation). The vector table
// stores Float32 embeddings as BLOBs; cosine similarity is computed in Swift
// (no sqlite-vec extension needed). Foundation-only.

import Foundation
import SQLite3

public final class AgentStore {

    public struct ConversationRow {
        public let id: Int64
        public let title: String
        public let createdAt: Double
        public let updatedAt: Double
        public let currentCLI: String?
        public let currentModel: String?
        public let cwd: String?
    }

    public struct MessageRow {
        public let id: Int64
        public let role: String        // "user" | "assistant" | "tool" | "system"
        public let content: String
        public let kind: String?       // "text" | "thinking" | "tool" | "error"
        public let createdAt: Double
    }

    // MARK: - Lifecycle

    public static let shared: AgentStore? = AgentStore(databaseURL: AgentStore.defaultURL())

    private var db: OpaquePointer?
    private let queue: DispatchQueue
    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    public static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Sourcepad", isDirectory: true)
            .appendingPathComponent("agent.db")
    }

    public init?(databaseURL: URL) {
        self.queue = DispatchQueue(label: "sourcepad.agentstore")
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            NSLog("[Sourcepad] agent.db open failed at \(databaseURL.path)")
            return nil
        }
        self.db = handle
        _ = exec("PRAGMA journal_mode=WAL")
        _ = exec("PRAGMA synchronous=NORMAL")
        _ = exec("PRAGMA foreign_keys=ON")
        createSchema()
    }

    deinit { if let db { sqlite3_close(db) } }

    private func createSchema() {
        let ddl = """
        CREATE TABLE IF NOT EXISTS conversation (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            title         TEXT NOT NULL DEFAULT 'New conversation',
            created_at    REAL NOT NULL,
            updated_at    REAL NOT NULL,
            current_cli   TEXT,
            current_model TEXT,
            cwd           TEXT,
            total_input_tokens  INTEGER NOT NULL DEFAULT 0,
            total_output_tokens INTEGER NOT NULL DEFAULT 0,
            total_cost_usd      REAL NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS conversation_session (
            conversation_id   INTEGER NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
            cli               TEXT NOT NULL,
            native_session_id TEXT NOT NULL,
            UNIQUE(conversation_id, cli)
        );
        CREATE TABLE IF NOT EXISTS message (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
            role            TEXT NOT NULL,
            content         TEXT NOT NULL,
            kind            TEXT,
            created_at      REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_message_conv ON message(conversation_id);
        CREATE TABLE IF NOT EXISTS tool_call (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            message_id INTEGER NOT NULL REFERENCES message(id) ON DELETE CASCADE,
            kind       TEXT,
            title      TEXT,
            detail     TEXT,
            status     TEXT
        );
        CREATE TABLE IF NOT EXISTS conversation_vec (
            conversation_id INTEGER NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
            dims            INTEGER NOT NULL,
            embed_model     TEXT,
            embedding       BLOB NOT NULL,
            UNIQUE(conversation_id)
        );
        """
        if !exec(ddl) { NSLog("[Sourcepad] agent.db schema creation failed") }
        migrate()
    }

    /// Add columns introduced after a DB was first created, bringing older
    /// agent.db files up to date. We check existing columns first so no spurious
    /// "duplicate column" errors are logged on every launch.
    private func migrate() {
        let existing = columnNames(of: "conversation")
        let additions = [
            ("total_input_tokens", "INTEGER NOT NULL DEFAULT 0"),
            ("total_output_tokens", "INTEGER NOT NULL DEFAULT 0"),
            ("total_cost_usd", "REAL NOT NULL DEFAULT 0"),
        ]
        for (name, decl) in additions where !existing.contains(name) {
            _ = exec("ALTER TABLE conversation ADD COLUMN \(name) \(decl)")
        }
    }

    private func columnNames(of table: String) -> Set<String> {
        queue.sync {
            guard let stmt = prepare("PRAGMA table_info(\(table))") else { return [] }
            defer { sqlite3_finalize(stmt) }
            var cols = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = textColumn(stmt, 1) { cols.insert(name) }   // column 1 = name
            }
            return cols
        }
    }

    // MARK: - Conversations

    @discardableResult
    public func createConversation(title: String, cwd: String?) -> Int64? {
        queue.sync {
            guard let stmt = prepare("""
                INSERT INTO conversation(title, created_at, updated_at, cwd)
                VALUES(?, ?, ?, ?)
                """) else { return nil }
            defer { sqlite3_finalize(stmt) }
            let now = Date().timeIntervalSince1970
            bindText(stmt, 1, title)
            sqlite3_bind_double(stmt, 2, now)
            sqlite3_bind_double(stmt, 3, now)
            bindText(stmt, 4, cwd)
            guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
            return sqlite3_last_insert_rowid(db)
        }
    }

    public func renameConversation(_ id: Int64, title: String) {
        run("UPDATE conversation SET title = ?, updated_at = ? WHERE id = ?") { stmt in
            self.bindText(stmt, 1, title)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 3, id)
        }
    }

    public func setCurrentCLIModel(_ id: Int64, cli: String?, model: String?) {
        run("UPDATE conversation SET current_cli = ?, current_model = ?, updated_at = ? WHERE id = ?") { stmt in
            self.bindText(stmt, 1, cli)
            self.bindText(stmt, 2, model)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 4, id)
        }
    }

    public func deleteConversation(_ id: Int64) {
        run("DELETE FROM conversation WHERE id = ?") { stmt in sqlite3_bind_int64(stmt, 1, id) }
    }

    /// Accumulate token/cost usage onto a conversation's running totals.
    public func addUsage(conversation id: Int64, input: Int, output: Int, cost: Double) {
        run("""
            UPDATE conversation SET
              total_input_tokens  = total_input_tokens  + ?,
              total_output_tokens = total_output_tokens + ?,
              total_cost_usd      = total_cost_usd      + ?
            WHERE id = ?
            """) { stmt in
            sqlite3_bind_int64(stmt, 1, Int64(input))
            sqlite3_bind_int64(stmt, 2, Int64(output))
            sqlite3_bind_double(stmt, 3, cost)
            sqlite3_bind_int64(stmt, 4, id)
        }
    }

    public func usage(conversation id: Int64) -> (input: Int, output: Int, cost: Double)? {
        queue.sync {
            guard let stmt = prepare("""
                SELECT total_input_tokens, total_output_tokens, total_cost_usd
                  FROM conversation WHERE id = ?
                """) else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return (Int(sqlite3_column_int64(stmt, 0)),
                    Int(sqlite3_column_int64(stmt, 1)),
                    sqlite3_column_double(stmt, 2))
        }
    }

    /// Most-recently-updated conversations first.
    public func recentConversations(limit: Int = 100) -> [ConversationRow] {
        queue.sync {
            guard let stmt = prepare("""
                SELECT id, title, created_at, updated_at, current_cli, current_model, cwd
                  FROM conversation ORDER BY updated_at DESC LIMIT ?
                """) else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var rows: [ConversationRow] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ConversationRow(
                    id: sqlite3_column_int64(stmt, 0),
                    title: textColumn(stmt, 1) ?? "",
                    createdAt: sqlite3_column_double(stmt, 2),
                    updatedAt: sqlite3_column_double(stmt, 3),
                    currentCLI: textColumn(stmt, 4),
                    currentModel: textColumn(stmt, 5),
                    cwd: textColumn(stmt, 6)))
            }
            return rows
        }
    }

    public func conversation(id: Int64) -> ConversationRow? {
        queue.sync {
            guard let stmt = prepare("""
                SELECT id, title, created_at, updated_at, current_cli, current_model, cwd
                  FROM conversation WHERE id = ?
                """) else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return ConversationRow(
                id: sqlite3_column_int64(stmt, 0),
                title: textColumn(stmt, 1) ?? "",
                createdAt: sqlite3_column_double(stmt, 2),
                updatedAt: sqlite3_column_double(stmt, 3),
                currentCLI: textColumn(stmt, 4),
                currentModel: textColumn(stmt, 5),
                cwd: textColumn(stmt, 6))
        }
    }

    // MARK: - Per-CLI native session ids (for native resume)

    public func setNativeSession(conversation id: Int64, cli: String, sessionID: String) {
        run("""
            INSERT INTO conversation_session(conversation_id, cli, native_session_id)
            VALUES(?, ?, ?)
            ON CONFLICT(conversation_id, cli) DO UPDATE SET native_session_id = excluded.native_session_id
            """) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            self.bindText(stmt, 2, cli)
            self.bindText(stmt, 3, sessionID)
        }
    }

    public func nativeSession(conversation id: Int64, cli: String) -> String? {
        queue.sync {
            guard let stmt = prepare(
                "SELECT native_session_id FROM conversation_session WHERE conversation_id = ? AND cli = ?")
            else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            bindText(stmt, 2, cli)
            return sqlite3_step(stmt) == SQLITE_ROW ? textColumn(stmt, 0) : nil
        }
    }

    // MARK: - Messages

    @discardableResult
    public func appendMessage(conversation id: Int64, role: String,
                              content: String, kind: String?) -> Int64? {
        queue.sync {
            guard let stmt = prepare("""
                INSERT INTO message(conversation_id, role, content, kind, created_at)
                VALUES(?, ?, ?, ?, ?)
                """) else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            bindText(stmt, 2, role)
            bindText(stmt, 3, content)
            bindText(stmt, 4, kind)
            sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
            // Bump the conversation's updated_at so history sorts correctly.
            touchUnsynced(id)
            return sqlite3_last_insert_rowid(db)
        }
    }

    public func messages(conversation id: Int64) -> [MessageRow] {
        queue.sync {
            guard let stmt = prepare("""
                SELECT id, role, content, kind, created_at FROM message
                 WHERE conversation_id = ? ORDER BY id ASC
                """) else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            var rows: [MessageRow] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(MessageRow(
                    id: sqlite3_column_int64(stmt, 0),
                    role: textColumn(stmt, 1) ?? "",
                    content: textColumn(stmt, 2) ?? "",
                    kind: textColumn(stmt, 3),
                    createdAt: sqlite3_column_double(stmt, 4)))
            }
            return rows
        }
    }

    // MARK: - Vector metadata (semantic recall)

    /// Store a conversation's embedding (Float32 vector) for semantic recall.
    public func setEmbedding(conversation id: Int64, vector: [Float], model: String?) {
        let blob = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        run("""
            INSERT INTO conversation_vec(conversation_id, dims, embed_model, embedding)
            VALUES(?, ?, ?, ?)
            ON CONFLICT(conversation_id) DO UPDATE SET
              dims = excluded.dims, embed_model = excluded.embed_model, embedding = excluded.embedding
            """) { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_bind_int(stmt, 2, Int32(vector.count))
            self.bindText(stmt, 3, model)
            _ = blob.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 4, raw.baseAddress, Int32(blob.count), Self.SQLITE_TRANSIENT)
            }
        }
    }

    /// Rank conversations by cosine similarity to `query`. Brute force over all
    /// stored embeddings — trivially fast at this scale (no sqlite-vec needed).
    public func semanticRank(query: [Float], limit: Int = 20) -> [(id: Int64, score: Float)] {
        queue.sync {
            guard let stmt = prepare("SELECT conversation_id, dims, embedding FROM conversation_vec")
            else { return [] }
            defer { sqlite3_finalize(stmt) }
            var scored: [(Int64, Float)] = []
            let qn = Self.norm(query)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let cid = sqlite3_column_int64(stmt, 0)
                let dims = Int(sqlite3_column_int(stmt, 1))
                guard dims == query.count,
                      let raw = sqlite3_column_blob(stmt, 2) else { continue }
                let bytes = Int(sqlite3_column_bytes(stmt, 2))
                let vec = [Float](unsafeUninitializedCapacity: dims) { buf, cnt in
                    memcpy(buf.baseAddress, raw, min(bytes, dims * MemoryLayout<Float>.stride))
                    cnt = dims
                }
                scored.append((cid, Self.cosine(query, vec, qn)))
            }
            return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { (id: $0.0, score: $0.1) }
        }
    }

    private static func norm(_ v: [Float]) -> Float {
        var s: Float = 0; for x in v { s += x * x }; return s.squareRoot()
    }
    private static func cosine(_ a: [Float], _ b: [Float], _ aNorm: Float) -> Float {
        var dot: Float = 0, bn: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; bn += b[i] * b[i] }
        let denom = aNorm * bn.squareRoot()
        return denom > 0 ? dot / denom : 0
    }

    // MARK: - Low-level helpers (mirrors ProjectIndex)

    private func touchUnsynced(_ id: Int64) {
        guard let stmt = prepare("UPDATE conversation SET updated_at = ? WHERE id = ?") else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 2, id)
        _ = sqlite3_step(stmt)
    }

    private func run(_ sql: String, bind: @escaping (OpaquePointer?) -> Void) {
        queue.sync {
            guard let stmt = prepare(sql) else { return }
            defer { sqlite3_finalize(stmt) }
            bind(stmt)
            _ = sqlite3_step(stmt)
        }
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        return queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                NSLog("[Sourcepad] agent.db exec failed: \(err.map { String(cString: $0) } ?? "?")")
                sqlite3_free(err)
                return false
            }
            return true
        }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            NSLog("[Sourcepad] agent.db prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_finalize(stmt)
            return nil
        }
        return stmt
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let v = value { sqlite3_bind_text(stmt, index, v, -1, Self.SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func textColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: raw)
    }
}
