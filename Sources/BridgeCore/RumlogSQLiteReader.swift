import Foundation
import SQLite3

public enum RumlogSQLiteReaderError: Error, LocalizedError {
    case missingFile(String)
    case openFailed(String)
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(path): return "RUMlog logbook not found at \(path)."
        case let .openFailed(message): return "Could not open the RUMlog logbook read-only: \(message)"
        case let .queryFailed(message): return "Could not read the RUMlog logbook: \(message)"
        }
    }
}

public struct RumlogSQLiteReader: Sendable {
    public static let snapshotVersion = 4
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func records() throws -> [ADIFRecord] {
        try records(whereClause: "ORDER BY id", bindID: nil, reserveCapacity: 70_000)
    }

    public func records(afterRowID rowID: Int64) throws -> [ADIFRecord] {
        try records(
            whereClause: "WHERE id > ? ORDER BY id",
            bindID: rowID,
            reserveCapacity: 256
        )
    }

    public func maximumRowID() throws -> Int64? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RumlogSQLiteReaderError.missingFile(fileURL.path)
        }
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(fileURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let database { sqlite3_close(database) }
            throw RumlogSQLiteReaderError.openFailed(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)
        _ = sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT MAX(id) FROM logbook", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    public func count() throws -> Int {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RumlogSQLiteReaderError.missingFile(fileURL.path)
        }
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(fileURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let database { sqlite3_close(database) }
            throw RumlogSQLiteReaderError.openFailed(message)
        }
        defer { sqlite3_close(database) }
        _ = sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM logbook", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    public func record(id: Int64) throws -> ADIFRecord? {
        try record(whereClause: "WHERE id = ? LIMIT 1", bindID: id)
    }

    public func latestRecord() throws -> ADIFRecord? {
        try record(whereClause: "ORDER BY datetime DESC, id DESC LIMIT 1", bindID: nil)
    }

    public func records(matching snapshot: QSOEditableSnapshot) throws -> [ADIFRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RumlogSQLiteReaderError.missingFile(fileURL.path)
        }
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(fileURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let database { sqlite3_close(database) }
            throw RumlogSQLiteReaderError.openFailed(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)
        _ = sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil)
        let sql = """
        \(Self.recordColumns) FROM logbook
        WHERE upper(callsign) = upper(?) AND datetime = ?
          AND lower(band) = lower(?) AND upper(mode) = upper(?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        let timestamp = "\(snapshot.qsoDate.prefix(4))-\(snapshot.qsoDate.dropFirst(4).prefix(2))-\(snapshot.qsoDate.suffix(2)) \(snapshot.timeOn.prefix(2)):\(snapshot.timeOn.dropFirst(2).prefix(2)):\(snapshot.timeOn.suffix(2))"
        let values = [snapshot.call, timestamp, snapshot.band, snapshot.mode]
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let result = value.withCString {
                sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, transient)
            }
            guard result == SQLITE_OK else {
                throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
            }
        }

        var matches: [ADIFRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            matches.append(Self.record(from: statement))
        }
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        return matches
    }

    private func records(
        whereClause: String,
        bindID: Int64?,
        reserveCapacity: Int
    ) throws -> [ADIFRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RumlogSQLiteReaderError.missingFile(fileURL.path)
        }
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(fileURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let database { sqlite3_close(database) }
            throw RumlogSQLiteReaderError.openFailed(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)
        _ = sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil)

        let sql = "\(Self.recordColumns) FROM logbook \(whereClause)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        if let bindID { sqlite3_bind_int64(statement, 1, bindID) }

        var result: [ADIFRecord] = []
        result.reserveCapacity(reserveCapacity)
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(Self.record(from: statement))
        }
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        return result
    }

    private func record(whereClause: String, bindID: Int64?) throws -> ADIFRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RumlogSQLiteReaderError.missingFile(fileURL.path)
        }
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(fileURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let database { sqlite3_close(database) }
            throw RumlogSQLiteReaderError.openFailed(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_000)
        _ = sqlite3_exec(database, "PRAGMA query_only=ON", nil, nil, nil)
        let sql = "\(Self.recordColumns) FROM logbook \(whereClause)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        if let bindID { sqlite3_bind_int64(statement, 1, bindID) }
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return Self.record(from: statement)
        case SQLITE_DONE: return nil
        default: throw RumlogSQLiteReaderError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static let recordColumns = """
    SELECT id, datetime, callsign, band, qrg, mode, rsttx, rstrx, qsl,
           lotwqsl, eqsl, dxcc, cq, itu, cnt, state, note, locator,
           manager, iota, satname, satmode, satrxband, power, dxccadif,
           name, qth, prefix, county, clublog, user_1, user_2, user_3,
           user_4
    """

    private static func record(from statement: OpaquePointer) -> ADIFRecord {
        let timestamp = text(statement, 1)
        let dateTime = splitTimestamp(timestamp)
        var fields: [String: String] = [
            "APP_RUMLOG_ROWID": String(sqlite3_column_int64(statement, 0)),
            "QSO_DATE": dateTime.date,
            "QSO_DATE_OFF": dateTime.date,
            "TIME_ON": dateTime.time,
            "TIME_OFF": dateTime.time,
            "CALL": decoded(text(statement, 2)),
            "BAND": text(statement, 3),
            "MODE": text(statement, 5),
            "RST_SENT": text(statement, 6),
            "RST_RCVD": text(statement, 7),
            "APP_RUMLOG_QSL": text(statement, 8),
            "APP_RUMLOG_LOTWQSL": text(statement, 9),
            "APP_RUMLOG_EQSL": text(statement, 10),
            "APP_RUMLOG_DXCC": text(statement, 11),
            "CQZ": text(statement, 12),
            "ITUZ": text(statement, 13),
            "CONT": text(statement, 14).uppercased(),
            "STATE": decoded(text(statement, 15)),
            "COMMENT": decoded(text(statement, 16)),
            "GRIDSQUARE": text(statement, 17),
            "QSL_VIA": decoded(text(statement, 18)),
            "IOTA": text(statement, 19),
            "SAT_NAME": text(statement, 20),
            "SAT_MODE": text(statement, 21),
            "BAND_RX": text(statement, 22),
            "TX_PWR": text(statement, 23),
            "APP_RUMLOG_POWER": text(statement, 23),
            "DXCC": String(sqlite3_column_int(statement, 24)),
            "NAME": decoded(text(statement, 25)),
            "QTH": decoded(text(statement, 26)),
            "PFX": text(statement, 27),
            "CNTY": decoded(text(statement, 28)),
            "APP_RUMLOG_USER_1": decoded(text(statement, 30)),
            "APP_RUMLOG_USER_2": decoded(text(statement, 31)),
            "APP_RUMLOG_USER_3": decoded(text(statement, 32)),
            "APP_RUMLOG_USER_4": decoded(text(statement, 33)),
            "APP_RUMLOG_COLORCODE": "0",
        ]
        if let khz = Double(text(statement, 4).replacingOccurrences(of: ",", with: ".")) {
            fields["FREQ"] = String(format: "%.6f", khz / 1_000)
        }
        if text(statement, 29) == "X" { fields["CLUBLOG_QSO_UPLOAD_STATUS"] = "Y" }
        return ADIFRecord(fields: fields)
    }
}

private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
    guard let value = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: value)
}

private func decoded(_ value: String) -> String {
    value.removingPercentEncoding ?? value
}

private func splitTimestamp(_ value: String) -> (date: String, time: String) {
    let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return ("", "") }
    return (
        parts[0].replacingOccurrences(of: "-", with: ""),
        parts[1].replacingOccurrences(of: ":", with: "")
    )
}
