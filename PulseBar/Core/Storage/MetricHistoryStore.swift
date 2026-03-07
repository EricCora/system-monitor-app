import Foundation
import SQLite3

public actor MetricHistoryStore {
    private let retentionPolicy: ChartHistoryRetentionPolicy
    private let pruneIntervalSeconds: TimeInterval = 10 * 60

    private var db: OpaquePointer?
    private var lastPruneAt = Date.distantPast
    private var startupErrorMessage: String?

    public init(
        databaseURL: URL? = nil,
        retentionPolicy: ChartHistoryRetentionPolicy = .thirtyDays
    ) {
        self.retentionPolicy = retentionPolicy

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

    public func append(samples: [MetricSample], now: Date = Date()) {
        guard let db, !samples.isEmpty else { return }

        let insertSQL = """
        INSERT OR REPLACE INTO metric_samples(metric_id, unit, value, ts)
        VALUES (?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        for sample in samples {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            sqlite3_bind_text(statement, 1, (sample.metricID.storageKey as NSString).utf8String, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, (sample.unit.rawValue as NSString).utf8String, -1, sqliteTransient)
            sqlite3_bind_double(statement, 3, sample.value)
            sqlite3_bind_int64(statement, 4, Int64(sample.timestamp.timeIntervalSince1970))
            _ = sqlite3_step(statement)
        }

        maybePrune(now: now)
    }

    public func latestByMetric() -> [MetricID: MetricSample] {
        guard let db else { return [:] }

        let sql = """
        SELECT metric_id, unit, value, MAX(ts)
        FROM metric_samples
        GROUP BY metric_id;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var results: [MetricID: MetricSample] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let metricIDCString = sqlite3_column_text(statement, 0),
                let unitCString = sqlite3_column_text(statement, 1)
            else {
                continue
            }

            let metricKey = String(cString: metricIDCString)
            let unitKey = String(cString: unitCString)
            guard
                let metricID = MetricID(storageKey: metricKey),
                let unit = MetricUnit(rawValue: unitKey)
            else {
                continue
            }

            results[metricID] = MetricSample(
                metricID: metricID,
                timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 3))),
                value: sqlite3_column_double(statement, 2),
                unit: unit
            )
        }

        return results
    }

    public func series(
        for metricID: MetricID,
        window: TimeWindow,
        now: Date = Date(),
        maxPoints: Int = 900
    ) -> [MetricSample] {
        loadSeries(
            for: metricID,
            seconds: window.seconds,
            bucketSeconds: 1,
            now: now,
            maxPoints: maxPoints
        )
    }

    public func series(
        for metricID: MetricID,
        window: MetricHistoryWindow,
        now: Date = Date(),
        maxPoints: Int = 900
    ) -> [MetricHistoryPoint] {
        loadSeries(
            for: metricID,
            seconds: window.seconds,
            bucketSeconds: window.bucketSeconds,
            now: now,
            maxPoints: maxPoints
        ).map {
            MetricHistoryPoint(
                timestamp: $0.timestamp,
                value: $0.value,
                unit: $0.unit
            )
        }
    }

    private func loadSeries(
        for metricID: MetricID,
        seconds: TimeInterval,
        bucketSeconds: Int,
        now: Date,
        maxPoints: Int
    ) -> [MetricSample] {
        guard let db else { return [] }

        let cutoff = Int64(now.timeIntervalSince1970 - seconds)
        let metricKey = metricID.storageKey
        let safeMaxPoints = max(1, maxPoints)

        let rows: [MetricSample]
        if bucketSeconds <= 1 {
            rows = loadRawRows(db: db, metricKey: metricKey, cutoff: cutoff)
        } else {
            rows = loadBucketedRows(
                db: db,
                metricKey: metricKey,
                cutoff: cutoff,
                bucketSeconds: Int64(bucketSeconds)
            )
        }

        if rows.isEmpty {
            return []
        }

        if rows.count <= safeMaxPoints {
            return rows
        }
        return Downsampler.downsample(rows, maxPoints: safeMaxPoints)
    }

    private static func createSchema(db: OpaquePointer?) throws {
        guard let db else { return }
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS metric_samples(
            metric_id TEXT NOT NULL,
            unit TEXT NOT NULL,
            value REAL NOT NULL,
            ts INTEGER NOT NULL,
            PRIMARY KEY(metric_id, ts)
        );
        CREATE INDEX IF NOT EXISTS idx_metric_samples_lookup
            ON metric_samples(metric_id, ts);
        """

        guard sqlite3_exec(db, schemaSQL, nil, nil, nil) == SQLITE_OK else {
            throw Self.sqliteError(db: db, fallback: "Unable to initialize metric history schema")
        }
    }

    private func maybePrune(now: Date) {
        guard let db else { return }
        guard now.timeIntervalSince(lastPruneAt) >= pruneIntervalSeconds else { return }
        lastPruneAt = now

        let cutoff = Int64(now.timeIntervalSince1970 - retentionPolicy.seconds)
        let sql = "DELETE FROM metric_samples WHERE ts < ?;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, cutoff)
        _ = sqlite3_step(statement)
    }

    private func loadRawRows(
        db: OpaquePointer,
        metricKey: String,
        cutoff: Int64
    ) -> [MetricSample] {
        let sql = """
        SELECT unit, value, ts
        FROM metric_samples
        WHERE metric_id = ? AND ts >= ?
        ORDER BY ts ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (metricKey as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 2, cutoff)

        var rows: [MetricSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let unitCString = sqlite3_column_text(statement, 0),
                  let metricID = MetricID(storageKey: metricKey),
                  let unit = MetricUnit(rawValue: String(cString: unitCString)) else {
                continue
            }

            rows.append(
                MetricSample(
                    metricID: metricID,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 2))),
                    value: sqlite3_column_double(statement, 1),
                    unit: unit
                )
            )
        }

        return rows
    }

    private func loadBucketedRows(
        db: OpaquePointer,
        metricKey: String,
        cutoff: Int64,
        bucketSeconds: Int64
    ) -> [MetricSample] {
        let sql = """
        SELECT
            unit,
            AVG(value),
            (ts / ?) * ? AS bucket_ts
        FROM metric_samples
        WHERE metric_id = ? AND ts >= ?
        GROUP BY bucket_ts, unit
        ORDER BY bucket_ts ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, bucketSeconds)
        sqlite3_bind_int64(statement, 2, bucketSeconds)
        sqlite3_bind_text(statement, 3, (metricKey as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 4, cutoff)

        var rows: [MetricSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let unitCString = sqlite3_column_text(statement, 0),
                  let metricID = MetricID(storageKey: metricKey),
                  let unit = MetricUnit(rawValue: String(cString: unitCString)) else {
                continue
            }

            rows.append(
                MetricSample(
                    metricID: metricID,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 2))),
                    value: sqlite3_column_double(statement, 1),
                    unit: unit
                )
            )
        }

        return rows
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
        let directory = appSupport.appendingPathComponent("PulseBar", isDirectory: true)
        return directory.appendingPathComponent("MetricHistory.sqlite")
    }

    private static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func openDatabase(at url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw sqliteError(db: db, fallback: "Unable to open metric history database")
        }
        return db
    }

    private static func sqliteError(db: OpaquePointer?, fallback: String) -> Error {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? fallback
        return ProviderError.unavailable(message)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
