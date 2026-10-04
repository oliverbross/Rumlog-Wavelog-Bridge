import Foundation

public struct BridgeSettings: Codable, Equatable, Sendable {
    public var wavelogBaseURL: String
    public var stationID: Int
    public var stationName: String
    public var rumlogBundleIdentifier: String
    public var rumlogLogbookPath: String?
    public var rumlogUDPPort: UInt16
    public var pollIntervalSeconds: Int
    public var bootstrapPageSize: Int
    public var automaticSync: Bool

    public init(
        wavelogBaseURL: String = "https://om0rx.wavelog.online/index.php",
        stationID: Int = 1,
        stationName: String = "Podkylava",
        rumlogBundleIdentifier: String = "de.dl2rum.RUMlogNG",
        rumlogLogbookPath: String? = nil,
        rumlogUDPPort: UInt16 = 12060,
        pollIntervalSeconds: Int = 60,
        bootstrapPageSize: Int = 500,
        automaticSync: Bool = false
    ) {
        self.wavelogBaseURL = wavelogBaseURL
        self.stationID = stationID
        self.stationName = stationName
        self.rumlogBundleIdentifier = rumlogBundleIdentifier
        self.rumlogLogbookPath = rumlogLogbookPath
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
    private let reconciliationURL: URL
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
        reconciliationURL = base.appendingPathComponent("reconciliation.json")
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
        let scopedURL = stationStateURL(prefix: "bootstrap", stationID: stationID)
        if FileManager.default.fileExists(atPath: scopedURL.path) {
            return try decoder.decode(BootstrapState.self, from: Data(contentsOf: scopedURL))
        }
        guard FileManager.default.fileExists(atPath: bootstrapURL.path) else {
            return BootstrapState(stationID: stationID)
        }
        let data = try Data(contentsOf: bootstrapURL)
        let saved = try decoder.decode(BootstrapState.self, from: data)
        guard saved.stationID == stationID else { return BootstrapState(stationID: stationID) }
        try atomicWrite(data, to: scopedURL)
        return saved
    }

    public func saveBootstrapState(_ state: BootstrapState) throws {
        try atomicWrite(
            try encoder.encode(state),
            to: stationStateURL(prefix: "bootstrap", stationID: state.stationID)
        )
    }

    public func loadContinuousSyncState(stationID: Int) throws -> ContinuousSyncState {
        let scopedURL = stationStateURL(prefix: "sync", stationID: stationID)
        if FileManager.default.fileExists(atPath: scopedURL.path) {
            return try decoder.decode(ContinuousSyncState.self, from: Data(contentsOf: scopedURL))
        }
        guard FileManager.default.fileExists(atPath: syncURL.path) else {
            return ContinuousSyncState(stationID: stationID)
        }
        let data = try Data(contentsOf: syncURL)
        let saved = try decoder.decode(ContinuousSyncState.self, from: data)
        guard saved.stationID == stationID else { return ContinuousSyncState(stationID: stationID) }
        try atomicWrite(data, to: scopedURL)
        return saved
    }

    public func saveContinuousSyncState(_ state: ContinuousSyncState) throws {
        try atomicWrite(
            try encoder.encode(state),
            to: stationStateURL(prefix: "sync", stationID: state.stationID)
        )
    }

    public func loadReconciliationState(stationID: Int) throws -> ReconciliationState {
        let scopedURL = stationStateURL(prefix: "reconciliation", stationID: stationID)
        if FileManager.default.fileExists(atPath: scopedURL.path) {
            return try decoder.decode(ReconciliationState.self, from: Data(contentsOf: scopedURL))
        }
        guard FileManager.default.fileExists(atPath: reconciliationURL.path) else {
            return ReconciliationState(stationID: stationID)
        }
        let data = try Data(contentsOf: reconciliationURL)
        let saved = try decoder.decode(ReconciliationState.self, from: data)
        guard saved.stationID == stationID else { return ReconciliationState(stationID: stationID) }
        try atomicWrite(data, to: scopedURL)
        return saved
    }

    public func saveReconciliationState(_ state: ReconciliationState) throws {
        let compactEncoder = JSONEncoder()
        compactEncoder.dateEncodingStrategy = .iso8601
        try atomicWrite(
            try compactEncoder.encode(state),
            to: stationStateURL(prefix: "reconciliation", stationID: state.stationID)
        )
    }

    public func ledgerURL() -> URL {
        directoryURL.appendingPathComponent("ledger.json")
    }

    private func stationStateURL(prefix: String, stationID: Int) -> URL {
        directoryURL.appendingPathComponent("\(prefix)-station-\(stationID).json")
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
