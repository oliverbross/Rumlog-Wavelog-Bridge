import Foundation

public struct BridgeSettings: Codable, Equatable, Sendable {
    public var wavelogBaseURL: String
    public var stationID: Int
    public var stationName: String
    public var rumlogBundleIdentifier: String
    public var rumlogUDPPort: UInt16
    public var pollIntervalSeconds: Int
    public var bootstrapPageSize: Int
    public var automaticSync: Bool

    public init(
        wavelogBaseURL: String = "https://om0rx.wavelog.online/index.php",
        stationID: Int = 1,
        stationName: String = "Podkylava",
        rumlogBundleIdentifier: String = "de.dl2rum.RUMlogNG",
        rumlogUDPPort: UInt16 = 12060,
        pollIntervalSeconds: Int = 60,
        bootstrapPageSize: Int = 500,
        automaticSync: Bool = false
    ) {
        self.wavelogBaseURL = wavelogBaseURL
        self.stationID = stationID
        self.stationName = stationName
        self.rumlogBundleIdentifier = rumlogBundleIdentifier
        self.rumlogUDPPort = rumlogUDPPort
        self.pollIntervalSeconds = pollIntervalSeconds
        self.bootstrapPageSize = bootstrapPageSize
        self.automaticSync = automaticSync
    }
}

public struct BootstrapState: Codable, Equatable, Sendable {
    public var stationID: Int
    public var nextPage: Int
    public var importedCount: Int
    public var totalCount: Int
    public var lastFetchedID: Int?
    public var completed: Bool
    public var updatedAt: Date

    public init(
        stationID: Int,
        nextPage: Int = 1,
        importedCount: Int = 0,
        totalCount: Int = 0,
        lastFetchedID: Int? = nil,
        completed: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.stationID = stationID
        self.nextPage = nextPage
        self.importedCount = importedCount
        self.totalCount = totalCount
        self.lastFetchedID = lastFetchedID
        self.completed = completed
        self.updatedAt = updatedAt
    }
}

public struct ContinuousSyncState: Codable, Equatable, Sendable {
    public var stationID: Int
    public var lastWavelogID: Int?
    public var lastRumlogScanAt: Date?
    public var knownFingerprints: Set<String>
    public var lastSuccessAt: Date?
    public var pendingInboundFingerprints: Set<String>?

    public init(
        stationID: Int,
        lastWavelogID: Int? = nil,
        lastRumlogScanAt: Date? = nil,
        knownFingerprints: Set<String> = [],
        lastSuccessAt: Date? = nil,
        pendingInboundFingerprints: Set<String>? = nil
    ) {
        self.stationID = stationID
        self.lastWavelogID = lastWavelogID
        self.lastRumlogScanAt = lastRumlogScanAt
        self.knownFingerprints = knownFingerprints
        self.lastSuccessAt = lastSuccessAt
        self.pendingInboundFingerprints = pendingInboundFingerprints
    }
}

public actor BridgeFileStore {
    public let directoryURL: URL
    private let settingsURL: URL
    private let bootstrapURL: URL
    private let syncURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL? = nil) throws {
        let base = directoryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rumlog-Wavelog-Bridge", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.directoryURL = base
        settingsURL = base.appendingPathComponent("settings.json")
        bootstrapURL = base.appendingPathComponent("bootstrap.json")
        syncURL = base.appendingPathComponent("sync.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadSettings() throws -> BridgeSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return BridgeSettings() }
        return try decoder.decode(BridgeSettings.self, from: Data(contentsOf: settingsURL))
    }

    public func saveSettings(_ settings: BridgeSettings) throws {
        try atomicWrite(try encoder.encode(settings), to: settingsURL)
    }

    public func loadBootstrapState(stationID: Int) throws -> BootstrapState {
        guard FileManager.default.fileExists(atPath: bootstrapURL.path) else {
            return BootstrapState(stationID: stationID)
        }
        let saved = try decoder.decode(BootstrapState.self, from: Data(contentsOf: bootstrapURL))
        return saved.stationID == stationID ? saved : BootstrapState(stationID: stationID)
    }

    public func saveBootstrapState(_ state: BootstrapState) throws {
        try atomicWrite(try encoder.encode(state), to: bootstrapURL)
    }

    public func loadContinuousSyncState(stationID: Int) throws -> ContinuousSyncState {
        guard FileManager.default.fileExists(atPath: syncURL.path) else {
            return ContinuousSyncState(stationID: stationID)
        }
        let saved = try decoder.decode(ContinuousSyncState.self, from: Data(contentsOf: syncURL))
        return saved.stationID == stationID ? saved : ContinuousSyncState(stationID: stationID)
    }

    public func saveContinuousSyncState(_ state: ContinuousSyncState) throws {
        try atomicWrite(try encoder.encode(state), to: syncURL)
    }

    public func ledgerURL() -> URL {
        directoryURL.appendingPathComponent("ledger.json")
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
