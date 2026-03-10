import Foundation
import SQLite3

public actor TemperatureHistoryStore {
    private let defaultRetentionSeconds: Int64 = 40 * 24 * 60 * 60
    private var db: OpaquePointer?
    private var lastPruneAt = Date.distantPast
    private let pruneIntervalSeconds: TimeInterval = 10 * 60
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

    public func append(channels: [SensorReading]) {
        guard let db, !channels.isEmpty else { return }
        let insertSQL = """
        INSERT OR REPLACE INTO sensor_samples(sensor_id, channel_type, value, ts)
        VALUES (?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        for channel in channels {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            let sensorID = channel.id as NSString
            let channelType = channel.channelType.rawValue as NSString
            let timestamp = Int64(channel.timestamp.timeIntervalSince1970)

            sqlite3_bind_text(statement, 1, sensorID.utf8String, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, channelType.utf8String, -1, sqliteTransient)
            sqlite3_bind_double(statement, 3, channel.value)
            sqlite3_bind_int64(statement, 4, timestamp)
            _ = sqlite3_step(statement)
        }

        maybePrune(now: Date())
    }

    public func series(
        sensorID: String,
        channelType: SensorChannelType,
        window: ChartWindow,
        now: Date = Date(),
        maxPoints: Int = 900
    ) -> [TemperatureHistoryPoint] {
        guard let db else { return [] }

        let cutoff = Int64(now.timeIntervalSince1970 - window.seconds)
        let safeMaxPoints = max(1, maxPoints)

        let rows: [(ts: Int64, value: Double)] = if window.bucketSeconds <= 1 {
            loadRawRows(
                db: db,
                sensorID: sensorID,
                channelType: channelType.rawValue,
                cutoff: cutoff
            )
        } else {
            loadBucketedRows(
                db: db,
                sensorID: sensorID,
                channelType: channelType.rawValue,
                cutoff: cutoff,
                bucketSeconds: Int64(window.bucketSeconds)
            )
        }

        if rows.isEmpty {
            return []
        }

        let sampled = downsample(rows: rows, maxPoints: safeMaxPoints)
        return sampled.map {
            TemperatureHistoryPoint(
                sensorID: sensorID,
                timestamp: Date(timeIntervalSince1970: TimeInterval($0.ts)),
                value: $0.value,
                channelType: channelType
            )
        }
    }

    private static func createSchema(db: OpaquePointer?) throws {
        guard let db else { return }
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS sensor_samples(
            sensor_id TEXT NOT NULL,
            channel_type TEXT NOT NULL,
            value REAL NOT NULL,
            ts INTEGER NOT NULL,
            PRIMARY KEY(sensor_id, channel_type, ts)
        );
        CREATE INDEX IF NOT EXISTS idx_sensor_samples_lookup
            ON sensor_samples(sensor_id, channel_type, ts);
        """
        guard sqlite3_exec(db, schemaSQL, nil, nil, nil) == SQLITE_OK else {
            throw Self.sqliteError(db: db, fallback: "Unable to initialize temperature history schema")
        }
    }

    private func maybePrune(now: Date) {
        guard let db else { return }
        guard now.timeIntervalSince(lastPruneAt) >= pruneIntervalSeconds else { return }
        lastPruneAt = now

        let cutoff = Int64(now.timeIntervalSince1970) - defaultRetentionSeconds
        let pruneSQL = "DELETE FROM sensor_samples WHERE ts < ?;"
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
        sensorID: String,
        channelType: String,
        cutoff: Int64
    ) -> [(ts: Int64, value: Double)] {
        let sql = """
        SELECT ts, value
        FROM sensor_samples
        WHERE sensor_id = ? AND channel_type = ? AND ts >= ?
        ORDER BY ts ASC;
        """
        return executeRowQuery(
            db: db,
            sql: sql,
            sensorID: sensorID,
            channelType: channelType,
            cutoff: cutoff
        )
    }

    private func loadBucketedRows(
        db: OpaquePointer,
        sensorID: String,
        channelType: String,
        cutoff: Int64,
        bucketSeconds: Int64
    ) -> [(ts: Int64, value: Double)] {
        let sql = """
        SELECT (ts / ?) * ? AS bucket_ts, AVG(value) AS avg_value
        FROM sensor_samples
        WHERE sensor_id = ? AND channel_type = ? AND ts >= ?
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
        sqlite3_bind_text(statement, 3, (sensorID as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_text(statement, 4, (channelType as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 5, cutoff)

        var rows: [(Int64, Double)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((sqlite3_column_int64(statement, 0), sqlite3_column_double(statement, 1)))
        }
        return rows
    }

    private func executeRowQuery(
        db: OpaquePointer,
        sql: String,
        sensorID: String,
        channelType: String,
        cutoff: Int64
    ) -> [(ts: Int64, value: Double)] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (sensorID as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, (channelType as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 3, cutoff)

        var rows: [(Int64, Double)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((sqlite3_column_int64(statement, 0), sqlite3_column_double(statement, 1)))
        }
        return rows
    }

    private func downsample(rows: [(ts: Int64, value: Double)], maxPoints: Int) -> [(ts: Int64, value: Double)] {
        if rows.count <= maxPoints {
            return rows
        }
        let stride = max(1, Int(ceil(Double(rows.count) / Double(maxPoints))))
        var result: [(ts: Int64, value: Double)] = []
        result.reserveCapacity(maxPoints)

        var index = 0
        while index < rows.count {
            result.append(rows[index])
            index += stride
        }
        if let last = rows.last, result.last?.ts != last.ts {
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
            .appendingPathComponent("temperature-history.sqlite3")
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
            throw NSError(domain: "TemperatureHistoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return db!
    }

    private static func sqliteError(db: OpaquePointer, fallback: String) -> Error {
        let raw = sqlite3_errmsg(db)
        if let raw {
            return NSError(
                domain: "TemperatureHistoryStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(cString: raw)]
            )
        }
        return NSError(domain: "TemperatureHistoryStore", code: 3, userInfo: [NSLocalizedDescriptionKey: fallback])
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
