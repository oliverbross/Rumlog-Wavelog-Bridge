import Foundation

public enum RumlogMessageKind: String, Codable, Sendable {
    case appInfo = "app_info"
    case contactInfo = "contact_info"
    case contactReplace = "contact_replace"
    case contactDelete = "contact_delete"
    case unknown

    init(rootElement: String) {
        switch rootElement.lowercased() {
        case "appinfo": self = .appInfo
        case "contactinfo": self = .contactInfo
        case "contactreplace": self = .contactReplace
        case "contactdelete": self = .contactDelete
        default: self = .unknown
        }
    }
}

public struct RumlogPeerMessage: Codable, Equatable, Sendable {
    public let kind: RumlogMessageKind
    public let rootElement: String
    public let fields: [String: String]

    public init(rootElement: String, fields: [String: String]) {
        self.rootElement = rootElement.lowercased()
        self.kind = RumlogMessageKind(rootElement: rootElement)
        self.fields = fields.reduce(into: [:]) { result, field in
            result[field.key.lowercased()] = field.value
        }
    }

    public subscript(field: String) -> String? {
        fields[field.lowercased()]
    }

    public var contactID: String? { self["id"] }
    public var callsign: String? { self["call"] }
    public var timestamp: String? { self["timestamp"] }
    public var oldCallsign: String? { self["oldcall"] }
    public var oldTimestamp: String? { self["oldtimestamp"] }
}

public struct RumlogCaptureRecord: Codable, Sendable {
    public let sequence: UInt64
    public let receivedAt: Date
    public let sourceAddress: String
    public let sourcePort: UInt16
    public let byteCount: Int
    public let message: RumlogPeerMessage?
    public let parseError: String?
    public let rawXML: String?

    public init(
        sequence: UInt64,
        receivedAt: Date,
        sourceAddress: String,
        sourcePort: UInt16,
        byteCount: Int,
        message: RumlogPeerMessage?,
        parseError: String?,
        rawXML: String?
    ) {
        self.sequence = sequence
        self.receivedAt = receivedAt
        self.sourceAddress = sourceAddress
        self.sourcePort = sourcePort
        self.byteCount = byteCount
        self.message = message
        self.parseError = parseError
        self.rawXML = rawXML
    }
}
