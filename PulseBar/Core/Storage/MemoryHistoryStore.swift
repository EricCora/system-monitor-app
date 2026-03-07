import Foundation
import SQLite3

public actor MemoryHistoryStore {
    private let defaultRetentionSeconds: Int64 = 40 * 24 * 60 * 60
    private let pruneIntervalSeconds: TimeInterval = 10 * 60

    private var db: OpaquePointer?
    private var lastPruneAt = Date.distantPast
    private var startupErrorMessage: String?

    public init(databaseURL: URL? = nil) {
        var openedDB: OpaquePointer?
        do {
            let resolvedURL = try Self.resolveDatabaseURL(explicit: databaseURL)
            try Self.ensureDirectoryExists(resolvedURL.deletingLastPathComponent())
            openedDB = try Self.openDatabase(at: resolvedURL)
            try Self.createSchema(db: openedDB)
            db = openedDB
        } catch {
            if let openedDB {
                sqlite3_close(openedDB)
            }
            startupErrorMessage = error.localizedDescription
            db = nil
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public func startupError() -> String? {
        startupErrorMessage
    }

    public func append(point: MemoryHistoryPoint) {
        guard let db else { return }

        let insertSQL = """
        INSERT OR REPLACE INTO memory_samples(
            ts, app_bytes, wired_bytes, active_bytes, compressed_bytes,
            cache_bytes, free_bytes, total_bytes, pressure_percent
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(point.timestamp.timeIntervalSince1970))
        sqlite3_bind_double(statement, 2, point.appBytes)
        sqlite3_bind_double(statement, 3, point.wiredBytes)
        sqlite3_bind_double(statement, 4, point.activeBytes)
        sqlite3_bind_double(statement, 5, point.compressedBytes)
        sqlite3_bind_double(statement, 6, point.cacheBytes)
        sqlite3_bind_double(statement, 7, point.freeBytes)
        sqlite3_bind_double(statement, 8, point.totalBytes)
        sqlite3_bind_double(statement, 9, point.pressurePercent)
        _ = sqlite3_step(statement)

        maybePrune(now: Date())
    }

    public func series(
        window: MemoryHistoryWindow,
        now: Date = Date(),
        maxPoints: Int = 900
    ) -> [MemoryHistoryPoint] {
        guard let db else { return [] }

        let cutoff = Int64(now.timeIntervalSince1970 - window.seconds)
        let safeMaxPoints = max(1, maxPoints)

        let rows: [MemoryHistoryPoint] = if window.bucketSeconds <= 1 {
            loadRawRows(db: db, cutoff: cutoff)
        } else {
            loadBucketedRows(db: db, cutoff: cutoff, bucketSeconds: Int64(window.bucketSeconds))
        }

        if rows.isEmpty {
            return []
        }
        return downsample(rows: rows, maxPoints: safeMaxPoints)
    }

    private static func createSchema(db: OpaquePointer?) throws {
        guard let db else { return }
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS memory_samples(
            ts INTEGER PRIMARY KEY,
            app_bytes REAL NOT NULL,
            wired_bytes REAL NOT NULL,
            active_bytes REAL NOT NULL,
            compressed_bytes REAL NOT NULL,
            cache_bytes REAL NOT NULL,
            free_bytes REAL NOT NULL,
            total_bytes REAL NOT NULL,
            pressure_percent REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_memory_samples_ts
            ON memory_samples(ts);
        """
        guard sqlite3_exec(db, schemaSQL, nil, nil, nil) == SQLITE_OK else {
            throw Self.sqliteError(db: db, fallback: "Unable to initialize memory history schema")
        }
    }

    private func maybePrune(now: Date) {
        guard let db else { return }
        guard now.timeIntervalSince(lastPruneAt) >= pruneIntervalSeconds else { return }
        lastPruneAt = now

        let cutoff = Int64(now.timeIntervalSince1970) - defaultRetentionSeconds
        let pruneSQL = "DELETE FROM memory_samples WHERE ts < ?;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, pruneSQL, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, cutoff)
        _ = sqlite3_step(statement)
    }

    private func loadRawRows(
        db: OpaquePointer,
        cutoff: Int64
    ) -> [MemoryHistoryPoint] {
        let sql = """
        SELECT
            ts, app_bytes, wired_bytes, active_bytes, compressed_bytes,
            cache_bytes, free_bytes, total_bytes, pressure_percent
        FROM memory_samples
        WHERE ts >= ?
        ORDER BY ts ASC;
        """
        return executeRowsQuery(db: db, sql: sql, cutoff: cutoff)
    }

    private func loadBucketedRows(
        db: OpaquePointer,
        cutoff: Int64,
        bucketSeconds: Int64
    ) -> [MemoryHistoryPoint] {
        let sql = """
        SELECT
            (ts / ?) * ? AS bucket_ts,
            AVG(app_bytes),
            AVG(wired_bytes),
            AVG(active_bytes),
            AVG(compressed_bytes),
            AVG(cache_bytes),
            AVG(free_bytes),
            AVG(total_bytes),
            AVG(pressure_percent)
        FROM memory_samples
        WHERE ts >= ?
        GROUP BY bucket_ts
        ORDER BY bucket_ts ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, bucketSeconds)
        sqlite3_bind_int64(statement, 2, bucketSeconds)
        sqlite3_bind_int64(statement, 3, cutoff)

        var points: [MemoryHistoryPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            points.append(
                MemoryHistoryPoint(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0))),
                    appBytes: sqlite3_column_double(statement, 1),
                    wiredBytes: sqlite3_column_double(statement, 2),
                    activeBytes: sqlite3_column_double(statement, 3),
                    compressedBytes: sqlite3_column_double(statement, 4),
                    cacheBytes: sqlite3_column_double(statement, 5),
                    freeBytes: sqlite3_column_double(statement, 6),
                    totalBytes: sqlite3_column_double(statement, 7),
                    pressurePercent: sqlite3_column_double(statement, 8)
                )
            )
        }
        return points
    }

    private func executeRowsQuery(
        db: OpaquePointer,
        sql: String,
        cutoff: Int64
    ) -> [MemoryHistoryPoint] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, cutoff)

        var points: [MemoryHistoryPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            points.append(
                MemoryHistoryPoint(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0))),
                    appBytes: sqlite3_column_double(statement, 1),
                    wiredBytes: sqlite3_column_double(statement, 2),
                    activeBytes: sqlite3_column_double(statement, 3),
                    compressedBytes: sqlite3_column_double(statement, 4),
                    cacheBytes: sqlite3_column_double(statement, 5),
                    freeBytes: sqlite3_column_double(statement, 6),
                    totalBytes: sqlite3_column_double(statement, 7),
                    pressurePercent: sqlite3_column_double(statement, 8)
                )
            )
        }
        return points
    }

    private func downsample(rows: [MemoryHistoryPoint], maxPoints: Int) -> [MemoryHistoryPoint] {
        if rows.count <= maxPoints {
            return rows
        }

        let stride = max(1, Int(ceil(Double(rows.count) / Double(maxPoints))))
        var result: [MemoryHistoryPoint] = []
        result.reserveCapacity(maxPoints)

        var index = 0
        while index < rows.count {
            result.append(rows[index])
            index += stride
        }

        if let last = rows.last, result.last?.timestamp != last.timestamp {
            if result.count >= maxPoints {
                result[result.count - 1] = last
            } else {
                result.append(last)
            }
        }
        return result
    }

    private static func resolveDatabaseURL(explicit: URL?) throws -> URL {
        if let explicit {
            return explicit
        }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("PulseBar", isDirectory: true)
            .appendingPathComponent("memory-history.sqlite3")
    }

    private static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func openDatabase(at url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown sqlite error"
            if let db {
                sqlite3_close(db)
            }
            throw NSError(domain: "MemoryHistoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return db!
    }

    private static func sqliteError(db: OpaquePointer, fallback: String) -> Error {
        let raw = sqlite3_errmsg(db)
        if let raw {
            return NSError(
                domain: "MemoryHistoryStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(cString: raw)]
            )
        }
        return NSError(domain: "MemoryHistoryStore", code: 3, userInfo: [NSLocalizedDescriptionKey: fallback])
    }
}
