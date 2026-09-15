import Foundation
import SQLite3

public struct SearchHit: Sendable, Hashable, Identifiable {
    public let ref: PageRef
    public let title: String
    /// Фрагмент текста; совпадения обрамлены `SearchIndex.highlightStart` и `SearchIndex.highlightEnd`.
    public let snippet: String

    public var id: PageRef { ref }
}

enum SQLValue: Sendable {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null
}

/// Полнотекстовый индекс всех пространств и таблица ссылок для обратных ссылок.
/// Индекс — кэш: его можно удалить, он пересоберётся из файлов.
public actor SearchIndex {
    public static let highlightStart: Character = "\u{1}"
    public static let highlightEnd: Character = "\u{2}"
    /// Поиск по триграммам не находит слова короче трёх букв.
    public static let minimumTermLength = 3
    private static let schemaVersion = 1
    private static let busyTimeoutMilliseconds: Int32 = 5_000

    // Соединение принадлежит только этому актору; закрывается в deinit, когда других ссылок нет.
    private nonisolated(unsafe) let database: OpaquePointer

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(String.filePath(url), &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "код \(status)"
            sqlite3_close_v2(handle)
            throw FolioError.database(message)
        }
        sqlite3_busy_timeout(handle, Self.busyTimeoutMilliseconds)
        do {
            try Self.migrate(handle)
        } catch {
            sqlite3_close_v2(handle)
            throw error
        }
        database = handle
    }

    deinit {
        sqlite3_close_v2(database)
    }

    /// Переиндексирует изменившиеся страницы пространства; возвращает число затронутых страниц.
    @discardableResult
    public func sync(_ snapshot: SpaceSnapshot) throws -> Int {
        let spaceKey = snapshot.space.id.uuidString
        // Сверка с базой внутри транзакции: приложение и утилита folio могут обновлять индекс одновременно.
        try run("BEGIN IMMEDIATE")
        do {
            let knownRows = try rows("SELECT path, id, mtime FROM documents WHERE space = ?", [.text(spaceKey)]) { statement in
                (Self.text(statement, 0), KnownDocument(id: sqlite3_column_int64(statement, 1), mtime: sqlite3_column_double(statement, 2)))
            }
            let known = Dictionary(knownRows, uniquingKeysWith: { first, _ in first })
            let changes = snapshot.pages.compactMap { path, node -> PendingDocument? in
                let mtime = Self.modificationTime(snapshot.fileURL(for: path))
                if let entry = known[path], entry.mtime == mtime { return nil }
                return PendingDocument(path: path, node: node, mtime: mtime, existingID: known[path]?.id)
            }
            let removed = known.filter { snapshot.pages[$0.key] == nil }.map(\.value.id)

            for change in changes {
                let text = (try? String(contentsOf: snapshot.fileURL(for: change.path), encoding: .utf8)) ?? ""
                let body = PageDocument.parse(text).body
                try upsert(spaceKey: spaceKey, change: change, body: body, links: WikiLinkParser.links(in: body))
            }
            for id in removed {
                try deleteDocument(id: id)
            }
            try run("COMMIT")
            return changes.count + removed.count
        } catch {
            try? run("ROLLBACK")
            throw error
        }
    }

    public func search(_ query: String, in spaceIDs: [UUID]? = nil, limit: Int = 50) throws -> [SearchHit] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= Self.minimumTermLength }
        guard !terms.isEmpty, spaceIDs?.isEmpty != true else { return [] }

        let match = terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " ")
        let spaceFilter = spaceIDs.map { ids in
            " AND d.space IN (\(Array(repeating: "?", count: ids.count).joined(separator: ", ")))"
        } ?? ""
        let sql = """
            SELECT d.space, d.path, d.title, snippet(documents_fts, 2, char(1), char(2), '…', 16)
            FROM documents_fts JOIN documents d ON d.id = documents_fts.rowid
            WHERE documents_fts MATCH ?\(spaceFilter)
            ORDER BY bm25(documents_fts, 10.0, 4.0, 1.0)
            LIMIT ?
            """
        let values: [SQLValue] = [.text(match)] + (spaceIDs ?? []).map { .text($0.uuidString) } + [.integer(Int64(limit))]
        return try rows(sql, values, Self.hit)
    }

    public func backlinks(to title: String, in space: Space) throws -> [SearchHit] {
        let sql = """
            SELECT DISTINCT d.space, d.path, d.title, ''
            FROM links l JOIN documents d ON d.id = l.document_id
            WHERE l.target_title = ? AND ((l.target_space IS NULL AND d.space = ?) OR l.target_space = ?)
            ORDER BY d.title
            """
        let values: [SQLValue] = [.text(TitleKey.make(title)), .text(space.id.uuidString), .text(TitleKey.make(space.name))]
        return try rows(sql, values, Self.hit)
    }

    public func removeSpace(_ id: UUID) throws {
        let key = SQLValue.text(id.uuidString)
        try run("DELETE FROM documents_fts WHERE rowid IN (SELECT id FROM documents WHERE space = ?)", key)
        try run("DELETE FROM links WHERE document_id IN (SELECT id FROM documents WHERE space = ?)", key)
        try run("DELETE FROM documents WHERE space = ?", key)
    }

    // MARK: - Запись

    private struct KnownDocument {
        let id: Int64
        let mtime: Double
    }

    private struct PendingDocument {
        let path: String
        let node: PageNode
        let mtime: Double
        let existingID: Int64?
    }

    private struct LinkTarget: Hashable {
        let space: String?
        let title: String
    }

    private func upsert(spaceKey: String, change: PendingDocument, body: String, links: [WikiLink]) throws {
        let id: Int64
        if let existingID = change.existingID {
            try run("UPDATE documents SET title = ?, mtime = ? WHERE id = ?", .text(change.node.title), .real(change.mtime), .integer(existingID))
            try run("DELETE FROM documents_fts WHERE rowid = ?", .integer(existingID))
            try run("DELETE FROM links WHERE document_id = ?", .integer(existingID))
            id = existingID
        } else {
            try run(
                "INSERT INTO documents (space, path, title, mtime) VALUES (?, ?, ?, ?)",
                .text(spaceKey), .text(change.path), .text(change.node.title), .real(change.mtime)
            )
            id = sqlite3_last_insert_rowid(database)
        }
        try run(
            "INSERT INTO documents_fts (rowid, title, labels, body) VALUES (?, ?, ?, ?)",
            .integer(id), .text(change.node.title), .text(change.node.labels.joined(separator: " ")), .text(body)
        )
        let targets = Set(links.map { LinkTarget(space: $0.space.map(TitleKey.make), title: TitleKey.make($0.title)) })
        for target in targets {
            try run(
                "INSERT INTO links (document_id, target_space, target_title) VALUES (?, ?, ?)",
                .integer(id), target.space.map(SQLValue.text) ?? .null, .text(target.title)
            )
        }
    }

    private func deleteDocument(id: Int64) throws {
        try run("DELETE FROM documents_fts WHERE rowid = ?", .integer(id))
        try run("DELETE FROM links WHERE document_id = ?", .integer(id))
        try run("DELETE FROM documents WHERE id = ?", .integer(id))
    }

    // MARK: - SQLite

    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private static func migrate(_ database: OpaquePointer) throws {
        if try userVersion(database) != schemaVersion {
            try exec(database, "DROP TABLE IF EXISTS links; DROP TABLE IF EXISTS documents_fts; DROP TABLE IF EXISTS documents;")
        }
        try exec(database, """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS documents (
                id INTEGER PRIMARY KEY,
                space TEXT NOT NULL,
                path TEXT NOT NULL,
                title TEXT NOT NULL,
                mtime REAL NOT NULL,
                UNIQUE (space, path)
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(title, labels, body, tokenize = 'trigram');
            CREATE TABLE IF NOT EXISTS links (
                document_id INTEGER NOT NULL,
                target_space TEXT,
                target_title TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS links_target ON links (target_title);
            CREATE INDEX IF NOT EXISTS links_document ON links (document_id);
            PRAGMA user_version = \(schemaVersion);
            """)
    }

    private static func userVersion(_ database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
            throw FolioError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    private static func exec(_ database: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "ошибка SQL"
            sqlite3_free(errorMessage)
            throw FolioError.database(message)
        }
    }

    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FolioError.database(String(cString: sqlite3_errmsg(database)))
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .integer(let number): sqlite3_bind_int64(statement, index, number)
            case .real(let number): sqlite3_bind_double(statement, index, number)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: SQLValue...) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else {
            throw FolioError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func rows<Row>(_ sql: String, _ values: [SQLValue], _ transform: (OpaquePointer) -> Row?) throws -> [Row] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [Row] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw FolioError.database(String(cString: sqlite3_errmsg(database))) }
            if let row = transform(statement) { result.append(row) }
        }
        return result
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private static func hit(_ statement: OpaquePointer) -> SearchHit? {
        guard let spaceID = UUID(uuidString: text(statement, 0)) else { return nil }
        return SearchHit(
            ref: PageRef(spaceID: spaceID, path: text(statement, 1)),
            title: text(statement, 2),
            snippet: text(statement, 3)
        )
    }

    private static func modificationTime(_ url: URL) -> Double {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }
}
