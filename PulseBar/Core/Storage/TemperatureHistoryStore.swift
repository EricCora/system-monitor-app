import Foundation
import SQLite3

public actor TemperatureHistoryStore {
    private let defaultRetentionSeconds: Int64 = 40 * 24 * 60 * 60
    private var databaseURL: URL?
    private var db: OpaquePointer?
    private var lastPruneAt = Date.distantPast
    private let pruneIntervalSeconds: TimeInterval = 10 * 60
    private var startupErrorMessage: String?

    public init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
        do {
            let resolvedURL = try Self.resolveDatabaseURL(explicit: databaseURL)
            self.databaseURL = resolvedURL
            try Self.ensureDirectoryExists(resolvedURL.deletingLastPathComponent())
            db = try Self.openDatabaseWithRecovery(at: resolvedURL)
        } catch {
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
        guard !channels.isEmpty else { return }
        guard ensureDatabaseReady() else { return }
        guard let currentDB = db else { return }

        if append(channels: channels, to: currentDB) {
            maybePrune(now: Date())
            return
        }

        guard recoverDatabaseIfPossible(), let recoveredDB = self.db else { return }
        guard append(channels: channels, to: recoveredDB) else { return }
        maybePrune(now: Date())
    }

    private func append(channels: [SensorReading], to db: OpaquePointer) -> Bool {
        let insertSQL = """
        INSERT OR REPLACE INTO sensor_samples(sensor_id, channel_type, value, ts)
        VALUES (?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            return false
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
            guard sqlite3_step(statement) == SQLITE_DONE else {
                return false
            }
        }
        return true
    }

    public func series(
        sensorID: String,
        channelType: SensorChannelType,
        window: ChartWindow,
        now: Date = Date(),
        maxPoints: Int = 900
    ) -> [TemperatureHistoryPoint] {
        let cutoff = Int64(now.timeIntervalSince1970 - window.seconds)
        let safeMaxPoints = max(1, maxPoints)

        guard let rows = loadSeriesRows(
            sensorID: sensorID,
            channelType: channelType,
            cutoff: cutoff,
            bucketSeconds: window.bucketSeconds
        ) else {
            return []
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

    private func loadSeriesRows(
        sensorID: String,
        channelType: SensorChannelType,
        cutoff: Int64,
        bucketSeconds: Int
    ) -> [(ts: Int64, value: Double)]? {
        guard let activeDB = activeDatabaseForRead() else { return nil }
        let initialRows = loadRows(
            db: activeDB,
            sensorID: sensorID,
            channelType: channelType.rawValue,
            cutoff: cutoff,
            bucketSeconds: bucketSeconds
        )
        if let initialRows {
            return initialRows
        }

        guard recoverDatabaseIfPossible(), let recoveredDB = self.db else {
            return nil
        }
        return loadRows(
            db: recoveredDB,
            sensorID: sensorID,
            channelType: channelType.rawValue,
            cutoff: cutoff,
            bucketSeconds: bucketSeconds
        )
    }

    private func loadRows(
        db: OpaquePointer,
        sensorID: String,
        channelType: String,
        cutoff: Int64,
        bucketSeconds: Int
    ) -> [(ts: Int64, value: Double)]? {
        if bucketSeconds <= 1 {
            return loadRawRows(
                db: db,
                sensorID: sensorID,
                channelType: channelType,
                cutoff: cutoff
            )
        }

        return loadBucketedRows(
            db: db,
            sensorID: sensorID,
            channelType: channelType,
            cutoff: cutoff,
            bucketSeconds: Int64(bucketSeconds)
        )
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

    private static func openDatabaseWithRecovery(at url: URL) throws -> OpaquePointer {
        do {
            return try openAndPrepareDatabase(at: url)
        } catch {
            guard isRecoverableDatabaseError(error),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw error
            }

            try backupCorruptedDatabase(at: url)
            return try openAndPrepareDatabase(at: url)
        }
    }

    private static func openAndPrepareDatabase(at url: URL) throws -> OpaquePointer {
        var openedDB: OpaquePointer?
        do {
            openedDB = try Self.openDatabase(at: url)
            try Self.createSchema(db: openedDB)
            try Self.validateDatabase(db: openedDB)
            return openedDB!
        } catch {
            if let openedDB {
                sqlite3_close(openedDB)
            }
            throw error
        }
    }

    private static func isRecoverableDatabaseError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("malformed")
            || message.contains("not a database")
            || message.contains("database disk image is malformed")
    }

    private static func validateDatabase(db: OpaquePointer?) throws {
        guard let db else { return }

        let readSQL = "SELECT 1 FROM sensor_samples LIMIT 1;"
        var readStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, readSQL, -1, &readStatement, nil) == SQLITE_OK else {
            throw sqliteError(db: db, fallback: "Unable to validate temperature history database")
        }
        defer { sqlite3_finalize(readStatement) }

        let stepResult = sqlite3_step(readStatement)
        guard stepResult == SQLITE_ROW || stepResult == SQLITE_DONE else {
            throw sqliteError(db: db, fallback: "Unable to validate temperature history database")
        }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(db: db, fallback: "Unable to validate temperature history database")
        }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }

        let writeSQL = """
        INSERT OR REPLACE INTO sensor_samples(sensor_id, channel_type, value, ts)
        VALUES ('__validation__', 'temperatureCelsius', 0, 0);
        """
        guard sqlite3_exec(db, writeSQL, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(db: db, fallback: "Unable to validate temperature history database")
        }
    }

    private static func backupCorruptedDatabase(at url: URL) throws {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupBaseURL = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(timestamp)")
            .appendingPathExtension(url.pathExtension)

        try moveItemIfPresent(from: url, to: backupBaseURL)
        try moveSQLiteSidecarIfPresent(from: url, to: backupBaseURL, suffix: "-wal")
        try moveSQLiteSidecarIfPresent(from: url, to: backupBaseURL, suffix: "-shm")
    }

    private static func moveSQLiteSidecarIfPresent(from originalURL: URL, to backupURL: URL, suffix: String) throws {
        let originalSidecarURL = URL(fileURLWithPath: originalURL.path + suffix)
        let backupSidecarURL = URL(fileURLWithPath: backupURL.path + suffix)
        try moveItemIfPresent(from: originalSidecarURL, to: backupSidecarURL)
    }

    private static func moveItemIfPresent(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func ensureDatabaseReady() -> Bool {
        if db != nil {
            return true
        }
        return recoverDatabaseIfPossible()
    }

    private func activeDatabaseForRead() -> OpaquePointer? {
        if ensureDatabaseReady(), let db {
            return db
        }
        return nil
    }

    private func recoverDatabaseIfPossible() -> Bool {
        guard let databaseURL else { return false }

        if let db {
            sqlite3_close(db)
            self.db = nil
        }

        do {
            self.db = try Self.openDatabaseWithRecovery(at: databaseURL)
            startupErrorMessage = nil
            lastPruneAt = .distantPast
            return true
        } catch {
            startupErrorMessage = error.localizedDescription
            self.db = nil
            return false
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
    ) -> [(ts: Int64, value: Double)]? {
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
    ) -> [(ts: Int64, value: Double)]? {
        let sql = """
        SELECT (ts / ?) * ? AS bucket_ts, AVG(value) AS avg_value
        FROM sensor_samples
        WHERE sensor_id = ? AND channel_type = ? AND ts >= ?
        GROUP BY bucket_ts
        ORDER BY bucket_ts ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, bucketSeconds)
        sqlite3_bind_int64(statement, 2, bucketSeconds)
        sqlite3_bind_text(statement, 3, (sensorID as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_text(statement, 4, (channelType as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 5, cutoff)

        var rows: [(Int64, Double)] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                rows.append((sqlite3_column_int64(statement, 0), sqlite3_column_double(statement, 1)))
                continue
            }
            guard stepResult == SQLITE_DONE else {
                return nil
            }
            break
        }
        return rows
    }

    private func executeRowQuery(
        db: OpaquePointer,
        sql: String,
        sensorID: String,
        channelType: String,
        cutoff: Int64
    ) -> [(ts: Int64, value: Double)]? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (sensorID as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, (channelType as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 3, cutoff)

        var rows: [(Int64, Double)] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                rows.append((sqlite3_column_int64(statement, 0), sqlite3_column_double(statement, 1)))
                continue
            }
            guard stepResult == SQLITE_DONE else {
                return nil
            }
            break
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
