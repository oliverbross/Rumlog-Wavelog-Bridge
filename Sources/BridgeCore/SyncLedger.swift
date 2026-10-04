import Foundation

public enum SyncDirection: String, Codable, Sendable {
    case rumlogToWavelog = "rumlog_to_wavelog"
    case wavelogToRumlog = "wavelog_to_rumlog"
}

public enum SyncOperationKind: String, Codable, Sendable {
    case create
    case update
    case delete
    case confirmation
}

public enum DeliveryState: String, Codable, Sendable {
    case pending
    case deliveryUnknown = "delivery_unknown"
    case delivered
    case deadLetter = "dead_letter"
}

public struct ContactLink: Codable, Equatable, Sendable {
    public let rumlogID: String
    public var wavelogID: Int?
    public var semanticIdentityHash: String
    public var rumlogContentHash: String?
    public var wavelogContentHash: String?
    public var lastSeenInRumlog: Date?
    public var lastSeenInWavelog: Date?

    public init(
        rumlogID: String,
        wavelogID: Int? = nil,
        semanticIdentityHash: String,
        rumlogContentHash: String? = nil,
        wavelogContentHash: String? = nil,
        lastSeenInRumlog: Date? = nil,
        lastSeenInWavelog: Date? = nil
    ) {
        self.rumlogID = rumlogID
        self.wavelogID = wavelogID
        self.semanticIdentityHash = semanticIdentityHash
        self.rumlogContentHash = rumlogContentHash
        self.wavelogContentHash = wavelogContentHash
        self.lastSeenInRumlog = lastSeenInRumlog
        self.lastSeenInWavelog = lastSeenInWavelog
    }
}

public struct PendingOperation: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let direction: SyncDirection
    public let kind: SyncOperationKind
    public let rumlogID: String?
    public let wavelogID: Int?
    public let payloadHash: String
    public let createdAt: Date
    public var state: DeliveryState
    public var attempts: Int
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        direction: SyncDirection,
        kind: SyncOperationKind,
        rumlogID: String? = nil,
        wavelogID: Int? = nil,
        payloadHash: String,
        createdAt: Date = Date(),
        state: DeliveryState = .pending,
        attempts: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.direction = direction
        self.kind = kind
        self.rumlogID = rumlogID
        self.wavelogID = wavelogID
        self.payloadHash = payloadHash
        self.createdAt = createdAt
        self.state = state
        self.attempts = attempts
        self.lastError = lastError
    }
}

private struct LedgerState: Codable {
    var schemaVersion = 1
    var links: [String: ContactLink] = [:]
    var outbox: [PendingOperation] = []
}

public actor SyncLedger {
    private let fileURL: URL
    private var state: LedgerState

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try decoder.decode(LedgerState.self, from: data)
        } else {
            state = LedgerState()
        }
    }

    public func contactLink(rumlogID: String) -> ContactLink? {
        state.links[rumlogID]
    }

    public func contactLink(wavelogID: Int) -> ContactLink? {
        state.links.values.first { $0.wavelogID == wavelogID }
    }

    public func upsert(_ link: ContactLink) throws {
        state.links[link.rumlogID] = link
        try persist()
    }

    @discardableResult
    public func enqueue(_ operation: PendingOperation) throws -> UUID {
        if let existing = state.outbox.first(where: {
            $0.direction == operation.direction &&
                $0.kind == operation.kind &&
                $0.payloadHash == operation.payloadHash &&
                $0.state != .deadLetter
        }) {
            return existing.id
        }
        state.outbox.append(operation)
        try persist()
        return operation.id
    }

    public func pendingOperations() -> [PendingOperation] {
        state.outbox.filter { $0.state == .pending || $0.state == .deliveryUnknown }
    }

    public func mark(
        operationID: UUID,
        state newState: DeliveryState,
        error: String? = nil,
        incrementAttempts: Bool = false
    ) throws {
        guard let index = state.outbox.firstIndex(where: { $0.id == operationID }) else { return }
        state.outbox[index].state = newState
        state.outbox[index].lastError = error
        if incrementAttempts {
            state.outbox[index].attempts += 1
        }
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
