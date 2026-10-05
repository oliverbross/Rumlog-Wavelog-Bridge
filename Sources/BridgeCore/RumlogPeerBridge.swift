import Darwin
import Foundation

public enum RumlogPeerBridgeError: Error, LocalizedError {
    case socketFailure(String)
    case notConnected
    case invalidQSO
    case writeVerificationFailed

    public var errorDescription: String? {
        switch self {
        case let .socketFailure(message): return "RUMlog peer socket failed: \(message)"
        case .notConnected: return "RUMlog is not connected to the Wavelog Bridge peer. Enable ‘Listen to other RUMlog instances’ and tick Import for Wavelog Bridge in RUMlog Network status."
        case .invalidQSO: return "The QSO did not contain enough date, time, callsign, band, and mode data for RUMlog peer sync."
        case .writeVerificationFailed:
            return "RUMlog did not expose the requested replacement on readback; the reconciliation baseline was not advanced."
        }
    }
}

public final class RumlogPeerBridge: @unchecked Sendable {
    public typealias StateHandler = @Sendable (Bool, String) -> Void

    private let port: UInt16
    private let stationName: String
    private let logName: String
    private let stateHandler: StateHandler?
    private let queue = DispatchQueue(label: "com.oliverbross.rumlog-wavelog-bridge.peer")
    private let advertiserQueue = DispatchQueue(label: "com.oliverbross.rumlog-wavelog-bridge.advertiser")
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var advertiser: DispatchSourceTimer?
    private var listenerSocket: Int32 = -1
    private var connectionSocket: Int32 = -1
    private var running = false

    public init(port: UInt16, stationName: String = "Wavelog Bridge", logName: String, stateHandler: StateHandler? = nil) {
        self.port = port
        self.stationName = stationName
        self.logName = logName
        self.stateHandler = stateHandler
    }

    deinit { stop() }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connectionSocket >= 0
    }

    public func start() throws {
        lock.lock()
        let alreadyRunning = running
        lock.unlock()
        guard !alreadyRunning else { return }
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw socketError("create") }
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var noSigPipe: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(socketFD)
            throw socketError("bind 127.0.0.1:\(port)")
        }
        guard Darwin.listen(socketFD, 4) == 0 else {
            Darwin.close(socketFD)
            throw socketError("listen")
        }
        listenerSocket = socketFD
        lock.lock()
        running = true
        lock.unlock()
        stateHandler?(false, "Advertising Wavelog Bridge on port \(port)")
        let timer = DispatchSource.makeTimerSource(queue: advertiserQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(7))
        timer.setEventHandler { [weak self] in self?.advertise() }
        advertiser = timer
        timer.resume()
        queue.async { [weak self] in self?.run() }
    }

    public func stop() {
        advertiser?.cancel()
        advertiser = nil
        lock.lock()
        running = false
        let peer = connectionSocket
        connectionSocket = -1
        let listener = listenerSocket
        listenerSocket = -1
        lock.unlock()
        if peer >= 0 { Darwin.shutdown(peer, SHUT_RDWR) }
        if listener >= 0 {
            Darwin.shutdown(listener, SHUT_RDWR)
            Darwin.close(listener)
        }
    }

    public func sendReplacement(old: ADIFRecord, new: ADIFRecord) throws {
        guard
            let oldArchive = try RumlogQSOArchive.make(record: old, deletionIdentityOnly: true),
            let newArchive = try RumlogQSOArchive.make(record: new, deletionIdentityOnly: false)
        else { throw RumlogPeerBridgeError.invalidQSO }
        var replacement = message(kind: "QsoDeleted", archive: oldArchive)
        replacement.append(message(kind: "QsoLogged", archive: newArchive))
        try send(replacement)
    }

    private func run() {
        while isRunning {
            var address = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let accepted = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listenerSocket, $0, &length)
                }
            }
            if accepted < 0 {
                if isRunning { stateHandler?(false, "RUMlog peer accept failed") }
                continue
            }
            var noSigPipe: Int32 = 1
            setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
            lock.lock()
            if connectionSocket >= 0 { Darwin.close(connectionSocket) }
            connectionSocket = accepted
            lock.unlock()
            stateHandler?(true, "RUMlog connected to Wavelog Bridge")
            readPeer(accepted)
            lock.lock()
            if connectionSocket == accepted { connectionSocket = -1 }
            lock.unlock()
            Darwin.close(accepted)
            stateHandler?(false, "Waiting for RUMlog peer connection")
        }
    }

    private func readPeer(_ socketFD: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while isRunning {
            let count = Darwin.read(socketFD, &buffer, buffer.count)
            guard count > 0 else { break }
            let bytes = Data(buffer.prefix(count))
            if String(data: bytes, encoding: .utf8)?.contains("Ping") == true {
                try? writeAll(Data("Ping".utf8), to: socketFD)
            }
        }
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func advertise() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <AppInfo>
            <Application>RUMlogNG</Application>
            <AppVersion>RUMlog-Wavelog Bridge 0.2.1</AppVersion>
            <StationName>\(xmlEscaped(stationName))</StationName>
            <dbname>\(xmlEscaped(logName))</dbname>
            <ShownDxcc></ShownDxcc>
            <HdgToDxcc>-1</HdgToDxcc>
            <ShownStation></ShownStation>
            <HdgToStation>-1</HdgToStation>
            <CurrentBand></CurrentBand>
        </AppInfo>
        """
        let socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else { return }
        defer { Darwin.close(socketFD) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let data = Data(xml.utf8)
        data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = Darwin.sendto(socketFD, bytes.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func send(_ data: Data) throws {
        lock.lock()
        let socketFD = connectionSocket
        lock.unlock()
        guard socketFD >= 0 else { throw RumlogPeerBridgeError.notConnected }
        try writeAll(data, to: socketFD)
    }

    private func writeAll(_ data: Data, to socketFD: Int32) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let written = Darwin.write(socketFD, base.advanced(by: offset), data.count - offset)
                guard written > 0 else { throw socketError("write") }
                offset += written
            }
        }
    }

    private func message(kind: String, archive: Data) -> Data {
        RumlogPeerWire.message(kind: kind, archive: archive, stationName: stationName)
    }

    private func socketError(_ operation: String) -> RumlogPeerBridgeError {
        RumlogPeerBridgeError.socketFailure("\(operation): \(String(cString: strerror(errno)))")
    }
}

enum RumlogPeerWire {
    static func message(kind: String, archive: Data, stationName: String) -> Data {
        let encoded = archive.base64EncodedString()
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <RUMlogNG>
            <AppVersion>RUMlog-Wavelog Bridge 0.2.1</AppVersion>
            <StationName>\(xmlEscaped(stationName))</StationName>
            <\(kind)>
                <QSO_Data>\(encoded)</QSO_Data>
            </\(kind)>
        </RUMlogNG>B0UnDary_73
        """.utf8)
    }
}

@objc(QsoClass)
private final class QsoClass: NSObject, NSCoding {
    let objectValues: [String: Any]
    let integerValues: [String: Int64]
    let boolValues: [String: Bool]
    let doubleValues: [String: Double]

    init(
        objectValues: [String: Any],
        integerValues: [String: Int64],
        boolValues: [String: Bool],
        doubleValues: [String: Double]
    ) {
        self.objectValues = objectValues
        self.integerValues = integerValues
        self.boolValues = boolValues
        self.doubleValues = doubleValues
    }
    required init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        for (key, value) in objectValues {
            if value is NSNull { coder.encode(nil as Any?, forKey: key) }
            else { coder.encode(value, forKey: key) }
        }
        for (key, value) in integerValues { coder.encode(value, forKey: key) }
        for (key, value) in boolValues { coder.encode(value, forKey: key) }
        for (key, value) in doubleValues { coder.encode(value, forKey: key) }
    }
}

enum RumlogQSOArchive {
    static func make(record: ADIFRecord, deletionIdentityOnly: Bool) throws -> Data? {
        guard let snapshot = QSOEditableSnapshot(adif: record), let date = date(snapshot) else { return nil }
        let empty = ""
        let qrg = Double(snapshot.frequencyHz).map { $0 / 1_000 } ?? 0
        func value(_ key: String) -> String { deletionIdentityOnly ? empty : (record[key] ?? empty) }
        let objectValues: [String: Any] = [
            "band": snapshot.band,
            "callsign": snapshot.call,
            "clublog": deletionIdentityOnly ? empty : clublog(record),
            "cnt": deletionIdentityOnly ? NSNull() : continent(record["CONT"]),
            "contestNumRx": NSNull(), "contestNumTx": NSNull(),
            "county": value("CNTY"), "cq": value("CQZ"), "credits": empty,
            "dateString": deletionIdentityOnly ? NSNull() : displayDate(snapshot),
            "dateTime": date,
            "dxcc": record["APP_RUMLOG_DXCC"] ?? record["PFX"] ?? empty,
            "eqsl": deletionIdentityOnly ? NSNull() : confirmation(record, prefix: "EQSL"),
            "iota": value("IOTA"), "iotaCredits": empty, "itu": value("ITUZ"),
            "locator": value("GRIDSQUARE"),
            "lotwqsl": deletionIdentityOnly ? NSNull() : confirmation(record, prefix: "LOTW"),
            "manager": value("QSL_VIA"), "mode": snapshot.mode, "myCallsign": NSNull(),
            "name": value("NAME"), "note": deletionIdentityOnly ? NSNull() : snapshot.note,
            "power": deletionIdentityOnly ? empty : (record["APP_RUMLOG_POWER"] ?? record["TX_PWR"] ?? empty),
            "prefix": deletionIdentityOnly ? NSNull() : value("PFX"),
            "qrgString": deletionIdentityOnly ? NSNull() : formatQRG(qrg),
            "qsl": deletionIdentityOnly ? NSNull() : (record["APP_RUMLOG_QSL"] ?? empty),
            "qslInDate": empty, "qslInNsdate": NSNull(), "qslOutDate": empty, "qslOutNsdate": NSNull(),
            "qth": value("QTH"),
            "rstrx": deletionIdentityOnly ? NSNull() : value("RST_RCVD"),
            "rsttx": deletionIdentityOnly ? NSNull() : value("RST_SENT"),
            "satMode": value("SAT_MODE"), "satName": value("SAT_NAME"), "satRxBand": value("BAND_RX"),
            "sqlDateTime": sqlDate(snapshot), "state": value("STATE"),
            "timeString": deletionIdentityOnly ? NSNull() : String(snapshot.timeOn.prefix(4)),
            "user_1": value("APP_RUMLOG_USER_1"), "user_2": value("APP_RUMLOG_USER_2"),
            "user_3": value("APP_RUMLOG_USER_3"), "user_4": value("APP_RUMLOG_USER_4"),
            "uuid": NSNull(),
        ]
        let rowID = deletionIdentityOnly ? 0 : (Int64(record["APP_RUMLOG_ROWID"] ?? "") ?? 1)
        return try NSKeyedArchiver.archivedData(
            withRootObject: QsoClass(
                objectValues: objectValues,
                integerValues: [
                    "adif": Int64(record["DXCC"] ?? "0") ?? 0,
                    "colorCode": deletionIdentityOnly ? 0 : (Int64(record["APP_RUMLOG_COLORCODE"] ?? "0") ?? 0),
                    "rowid": rowID,
                ],
                boolValues: ["checked": false, "opIsValid": true],
                doubleValues: ["qrg": deletionIdentityOnly ? 0 : qrg]
            ),
            requiringSecureCoding: false
        )
    }

    private static func date(_ snapshot: QSOEditableSnapshot) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: snapshot.qsoDate + snapshot.timeOn)
    }

    private static func sqlDate(_ snapshot: QSOEditableSnapshot) -> String {
        "\(snapshot.qsoDate.prefix(4))-\(snapshot.qsoDate.dropFirst(4).prefix(2))-\(snapshot.qsoDate.suffix(2)) \(snapshot.timeOn.prefix(2)):\(snapshot.timeOn.dropFirst(2).prefix(2)):\(snapshot.timeOn.suffix(2))"
    }

    private static func displayDate(_ snapshot: QSOEditableSnapshot) -> String {
        "\(Int(snapshot.qsoDate.suffix(2)) ?? 0)/\(Int(snapshot.qsoDate.dropFirst(4).prefix(2)) ?? 0)/\(snapshot.qsoDate.prefix(4))"
    }

    private static func formatQRG(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func confirmation(_ record: ADIFRecord, prefix: String) -> String {
        let rumlogField = prefix == "LOTW" ? "APP_RUMLOG_LOTWQSL" : "APP_RUMLOG_\(prefix)"
        if let value = record[rumlogField], !value.isEmpty { return value }
        let received = record["\(prefix)_QSL_RCVD"] == "Y"
        let sent = record["\(prefix)_QSL_SENT"] == "Y"
        if received && sent { return "X" }
        if received { return "R" }
        if sent { return "S" }
        return ""
    }

    private static func clublog(_ record: ADIFRecord) -> String {
        record["CLUBLOG_QSO_UPLOAD_STATUS"] == "Y" ? "X" : ""
    }

    private static func continent(_ value: String?) -> String {
        guard let value else { return "" }
        return value.prefix(1).uppercased() + value.dropFirst().lowercased()
    }
}

private func xmlEscaped(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
