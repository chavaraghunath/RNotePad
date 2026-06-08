// SPDX-License-Identifier: MIT
// Sourcepad — SQLite-backed per-workspace index.
//
// One database per workspace at
//   ~/Library/Application Support/Sourcepad/Workspaces/<id>.db
//
// Schema (all operations go through this wrapper; no raw SQL elsewhere):
//
//   roots    (id, path UNIQUE)
//   files    (id, root_id → roots, rel_path, mtime, size, language, content_hash;
//             UNIQUE(root_id, rel_path), ON DELETE CASCADE from roots)
//   symbols  (id, file_id → files, name, kind, line, col;
//             ON DELETE CASCADE from files)
//   tags     (id, file_id → files, tag; ON DELETE CASCADE from files)
//   links    (id, from_file_id → files, target_path, kind;
//             ON DELETE CASCADE from files)
//
// Threading model: a single serial dispatch queue serialises all reads and
// writes through one connection. Indexer + UI both go through this; reads
// are sub-millisecond on warm caches so contention isn't an issue.
//
// SQLite is the system copy (macOS ships 3.39+) — we link -lsqlite3, no
// vendored amalgamation. Versions <3.20 lack ON DELETE CASCADE PRAGMA at
// open time; we set it explicitly.

import Foundation
import SQLite3

public final class ProjectIndex {

    public struct FileRow {
        public let id: Int64
        public let rootID: Int64
        public let relPath: String
        public let mtime: TimeInterval
        public let size: Int64
        public let language: String?
        public let contentHash: String?
    }

    public struct SymbolRow {
        public let fileID: Int64
        public let name: String
        public let kind: String?
        public let line: Int
        public let col: Int
    }

    public struct TagRow {
        public let fileID: Int64
        public let tag: String
    }

    public struct LinkRow {
        public let fromFileID: Int64
        public let targetPath: String
        public let kind: String?
    }

    // MARK: - Lifecycle

    private var db: OpaquePointer?
    private let queue: DispatchQueue
    private let url: URL

    public init?(databaseURL: URL) {
        self.url = databaseURL
        self.queue = DispatchQueue(label: "sourcepad.projectindex.\(databaseURL.lastPathComponent)")
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            NSLog("[Sourcepad] sqlite3_open_v2(\(databaseURL.path)) failed: rc=\(rc)")
            return nil
        }
        self.db = handle

        // Performance pragmas; WAL gives concurrent readers + faster writes;
        // NORMAL sync trades a tiny crash-recovery window for ~10x writes.
        _ = exec("PRAGMA journal_mode=WAL")
        _ = exec("PRAGMA synchronous=NORMAL")
        _ = exec("PRAGMA foreign_keys=ON")
        _ = exec("PRAGMA temp_store=MEMORY")
        _ = exec("PRAGMA cache_size=-8000")  // ~8 MB page cache

        createSchemaIfNeeded()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    public func close() {
        queue.sync {
            if let db { sqlite3_close(db) }
            db = nil
        }
    }

    // MARK: - Schema

    private func createSchemaIfNeeded() {
        let ddl = """
        CREATE TABLE IF NOT EXISTS roots (
            id   INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL UNIQUE
        );
        CREATE TABLE IF NOT EXISTS files (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            root_id      INTEGER NOT NULL REFERENCES roots(id) ON DELETE CASCADE,
            rel_path     TEXT NOT NULL,
            mtime        REAL NOT NULL,
            size         INTEGER NOT NULL,
            language     TEXT,
            content_hash TEXT,
            UNIQUE(root_id, rel_path)
        );
        CREATE INDEX IF NOT EXISTS idx_files_root      ON files(root_id);
        CREATE INDEX IF NOT EXISTS idx_files_rel_path  ON files(rel_path);

        CREATE TABLE IF NOT EXISTS symbols (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            name    TEXT NOT NULL,
            kind    TEXT,
            line    INTEGER NOT NULL,
            col     INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_symbols_file ON symbols(file_id);
        CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name);

        CREATE TABLE IF NOT EXISTS tags (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            tag     TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_tags_file ON tags(file_id);
        CREATE INDEX IF NOT EXISTS idx_tags_tag  ON tags(tag);

        CREATE TABLE IF NOT EXISTS links (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            from_file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            target_path  TEXT NOT NULL,
            kind         TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_links_from   ON links(from_file_id);
        CREATE INDEX IF NOT EXISTS idx_links_target ON links(target_path);
        """
        if !exec(ddl) {
            NSLog("[Sourcepad] failed to create ProjectIndex schema")
        }
    }

    // MARK: - Low-level helpers

    private func lastError() -> String {
        guard let db else { return "<no db>" }
        return String(cString: sqlite3_errmsg(db))
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        return queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db, sql, nil, nil, &err)
            if rc != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? "<no msg>"
                NSLog("[Sourcepad] sqlite exec failed: \(rc) — \(msg) — SQL: \(sql.prefix(200))")
                sqlite3_free(err)
                return false
            }
            return true
        }
    }

    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, index, v, -1, Self.SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindInt64(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, index, value)
    }

    private func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double) {
        sqlite3_bind_double(stmt, index, value)
    }

    private func textColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: raw)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            NSLog("[Sourcepad] sqlite prepare failed: \(lastError()) — SQL: \(sql.prefix(200))")
            sqlite3_finalize(stmt)
            return nil
        }
        return stmt
    }

    // MARK: - Roots

    /// Insert (or fetch) a root by absolute path and return its row id.
    @discardableResult
    public func upsertRoot(absolutePath: String) -> Int64? {
        return queue.sync {
            // Try to fetch first.
            if let existing = self.fetchRootIDUnsynced(path: absolutePath) {
                return existing
            }
            guard let stmt = self.prepare("INSERT INTO roots(path) VALUES(?)") else { return nil }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, absolutePath)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                NSLog("[Sourcepad] insert root failed: \(self.lastError())")
                return nil
            }
            return sqlite3_last_insert_rowid(self.db)
        }
    }

    private func fetchRootIDUnsynced(path: String) -> Int64? {
        guard let stmt = prepare("SELECT id FROM roots WHERE path = ?") else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, path)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
    }

    public func removeRoot(absolutePath: String) {
        guard let stmt = prepare("DELETE FROM roots WHERE path = ?") else { return }
        queue.sync {
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, absolutePath)
            _ = sqlite3_step(stmt)
        }
    }

    // MARK: - Files

    /// Insert-or-update a file row. Returns the row id.
    @discardableResult
    public func upsertFile(rootID: Int64,
                           relPath: String,
                           mtime: TimeInterval,
                           size: Int64,
                           language: String?,
                           contentHash: String?) -> Int64? {
        return queue.sync {
            // The ON CONFLICT clause is the upsert. We require SQLite 3.24+
            // which macOS has comfortably (the system SQLite is 3.39+).
            let sql = """
            INSERT INTO files(root_id, rel_path, mtime, size, language, content_hash)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(root_id, rel_path) DO UPDATE SET
              mtime = excluded.mtime,
              size = excluded.size,
              language = excluded.language,
              content_hash = excluded.content_hash
            """
            guard let stmt = self.prepare(sql) else { return nil }
            defer { sqlite3_finalize(stmt) }
            self.bindInt64(stmt, 1, rootID)
            self.bindText(stmt, 2, relPath)
            self.bindDouble(stmt, 3, mtime)
            self.bindInt64(stmt, 4, size)
            self.bindText(stmt, 5, language)
            self.bindText(stmt, 6, contentHash)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                NSLog("[Sourcepad] upsert file failed: \(self.lastError())")
                return nil
            }
            // last_insert_rowid is the inserted row only; on update we need
            // to look it up.
            if sqlite3_changes(self.db) == 1 && sqlite3_total_changes(self.db) > 0 {
                if let found = self.fetchFileIDUnsynced(rootID: rootID, relPath: relPath) {
                    return found
                }
            }
            return sqlite3_last_insert_rowid(self.db)
        }
    }

    private func fetchFileIDUnsynced(rootID: Int64, relPath: String) -> Int64? {
        guard let stmt = prepare("SELECT id FROM files WHERE root_id = ? AND rel_path = ?") else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        bindInt64(stmt, 1, rootID)
        bindText(stmt, 2, relPath)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
    }

    /// Delete a file (and its symbols / tags / links via CASCADE).
    public func removeFile(rootID: Int64, relPath: String) {
        guard let stmt = prepare("DELETE FROM files WHERE root_id = ? AND rel_path = ?") else { return }
        queue.sync {
            defer { sqlite3_finalize(stmt) }
            self.bindInt64(stmt, 1, rootID)
            self.bindText(stmt, 2, relPath)
            _ = sqlite3_step(stmt)
        }
    }

    /// Total count of indexed files across all roots.
    public func fileCount() -> Int {
        return queue.sync {
            guard let stmt = self.prepare("SELECT COUNT(*) FROM files") else { return 0 }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }
    }

    /// All known files, joined with the root path so callers can resolve
    /// absolute paths. Used by the upcoming ⌘P fuzzy file picker.
    public func allFiles() -> [(absolutePath: String, language: String?)] {
        return queue.sync {
            guard let stmt = self.prepare("""
                SELECT roots.path, files.rel_path, files.language
                  FROM files
                  JOIN roots ON files.root_id = roots.id
                """) else { return [] }
            defer { sqlite3_finalize(stmt) }
            var out: [(String, String?)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let root = self.textColumn(stmt, 0) ?? ""
                let rel  = self.textColumn(stmt, 1) ?? ""
                let lang = self.textColumn(stmt, 2)
                let abs = (root as NSString).appendingPathComponent(rel)
                out.append((abs, lang))
            }
            return out
        }
    }

    /// File row by (root, rel) — used to detect whether a re-index pass is needed.
    public func file(rootID: Int64, relPath: String) -> FileRow? {
        return queue.sync {
            guard let stmt = self.prepare("""
                SELECT id, root_id, rel_path, mtime, size, language, content_hash
                  FROM files WHERE root_id = ? AND rel_path = ?
                """) else { return nil }
            defer { sqlite3_finalize(stmt) }
            self.bindInt64(stmt, 1, rootID)
            self.bindText(stmt, 2, relPath)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return FileRow(
                id: sqlite3_column_int64(stmt, 0),
                rootID: sqlite3_column_int64(stmt, 1),
                relPath: self.textColumn(stmt, 2) ?? "",
                mtime: sqlite3_column_double(stmt, 3),
                size: sqlite3_column_int64(stmt, 4),
                language: self.textColumn(stmt, 5),
                contentHash: self.textColumn(stmt, 6))
        }
    }

    // MARK: - Symbols

    public func replaceSymbols(_ symbols: [SymbolRow], forFileID fileID: Int64) {
        queue.sync {
            // Wrap in a single transaction for atomicity + speed.
            var err: UnsafeMutablePointer<CChar>?
            sqlite3_exec(self.db, "BEGIN IMMEDIATE", nil, nil, &err)
            defer {
                sqlite3_exec(self.db, "COMMIT", nil, nil, &err)
                if err != nil { sqlite3_free(err) }
            }
            if let delStmt = self.prepare("DELETE FROM symbols WHERE file_id = ?") {
                self.bindInt64(delStmt, 1, fileID)
                _ = sqlite3_step(delStmt)
                sqlite3_finalize(delStmt)
            }
            guard let insStmt = self.prepare(
                "INSERT INTO symbols(file_id, name, kind, line, col) VALUES(?, ?, ?, ?, ?)") else { return }
            defer { sqlite3_finalize(insStmt) }
            for s in symbols {
                self.bindInt64(insStmt, 1, fileID)
                self.bindText(insStmt, 2, s.name)
                self.bindText(insStmt, 3, s.kind)
                sqlite3_bind_int(insStmt, 4, Int32(s.line))
                sqlite3_bind_int(insStmt, 5, Int32(s.col))
                _ = sqlite3_step(insStmt)
                sqlite3_reset(insStmt)
            }
        }
    }

    public func allSymbols() -> [(name: String, kind: String?, absolutePath: String, line: Int, col: Int)] {
        return queue.sync {
            guard let stmt = self.prepare("""
                SELECT symbols.name, symbols.kind, roots.path, files.rel_path,
                       symbols.line, symbols.col
                  FROM symbols
                  JOIN files ON files.id = symbols.file_id
                  JOIN roots ON roots.id = files.root_id
                """) else { return [] }
            defer { sqlite3_finalize(stmt) }
            var out: [(String, String?, String, Int, Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = self.textColumn(stmt, 0) ?? ""
                let kind = self.textColumn(stmt, 1)
                let root = self.textColumn(stmt, 2) ?? ""
                let rel  = self.textColumn(stmt, 3) ?? ""
                let line = Int(sqlite3_column_int(stmt, 4))
                let col  = Int(sqlite3_column_int(stmt, 5))
                let abs  = (root as NSString).appendingPathComponent(rel)
                out.append((name, kind, abs, line, col))
            }
            return out
        }
    }

    // MARK: - Tags + Links

    public func replaceTags(_ tags: [String], forFileID fileID: Int64) {
        queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            sqlite3_exec(self.db, "BEGIN IMMEDIATE", nil, nil, &err)
            defer {
                sqlite3_exec(self.db, "COMMIT", nil, nil, &err)
                if err != nil { sqlite3_free(err) }
            }
            if let delStmt = self.prepare("DELETE FROM tags WHERE file_id = ?") {
                self.bindInt64(delStmt, 1, fileID)
                _ = sqlite3_step(delStmt)
                sqlite3_finalize(delStmt)
            }
            guard let ins = self.prepare("INSERT INTO tags(file_id, tag) VALUES(?, ?)") else { return }
            defer { sqlite3_finalize(ins) }
            for t in tags {
                self.bindInt64(ins, 1, fileID)
                self.bindText(ins, 2, t)
                _ = sqlite3_step(ins)
                sqlite3_reset(ins)
            }
        }
    }

    public func replaceLinks(_ links: [(target: String, kind: String?)], forFileID fileID: Int64) {
        queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            sqlite3_exec(self.db, "BEGIN IMMEDIATE", nil, nil, &err)
            defer {
                sqlite3_exec(self.db, "COMMIT", nil, nil, &err)
                if err != nil { sqlite3_free(err) }
            }
            if let delStmt = self.prepare("DELETE FROM links WHERE from_file_id = ?") {
                self.bindInt64(delStmt, 1, fileID)
                _ = sqlite3_step(delStmt)
                sqlite3_finalize(delStmt)
            }
            guard let ins = self.prepare(
                "INSERT INTO links(from_file_id, target_path, kind) VALUES(?, ?, ?)") else { return }
            defer { sqlite3_finalize(ins) }
            for l in links {
                self.bindInt64(ins, 1, fileID)
                self.bindText(ins, 2, l.target)
                self.bindText(ins, 3, l.kind)
                _ = sqlite3_step(ins)
                sqlite3_reset(ins)
            }
        }
    }

    /// All files that link TO the given absolute target path. Used by the
    /// upcoming backlinks panel.
    public func backlinks(toAbsolute target: String) -> [String] {
        return queue.sync {
            guard let stmt = self.prepare("""
                SELECT roots.path, files.rel_path
                  FROM links
                  JOIN files ON files.id = links.from_file_id
                  JOIN roots ON roots.id = files.root_id
                 WHERE links.target_path = ?
                """) else { return [] }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, target)
            var out: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let root = self.textColumn(stmt, 0) ?? ""
                let rel  = self.textColumn(stmt, 1) ?? ""
                out.append((root as NSString).appendingPathComponent(rel))
            }
            return out
        }
    }
}
