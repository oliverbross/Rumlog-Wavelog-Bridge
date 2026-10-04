import CryptoKit
import Foundation

public struct SemanticQSOIdentity: Codable, Equatable, Hashable, Sendable {
    public let call: String
    public let timestamp: String
    public let band: String
    public let mode: String
    public let frequency: String

    public init(call: String, timestamp: String, band: String, mode: String, frequency: String = "") {
        self.call = Self.normalizeCall(call)
        self.timestamp = Self.normalizeTimestamp(timestamp)
        self.band = Self.normalizeBand(band)
        self.mode = Self.normalizeMode(mode)
        self.frequency = Self.normalizeFrequency(frequency)
    }

    public init?(message: RumlogPeerMessage) {
        guard
            let call = message.callsign,
            let timestamp = message.timestamp,
            let band = message["band"],
            let mode = message["mode"]
        else {
            return nil
        }
        self.init(
            call: call,
            timestamp: timestamp,
            band: band,
            mode: mode,
            frequency: message["txfreq"] ?? message["rxfreq"] ?? ""
        )
    }

    public var canonicalString: String {
        [call, timestamp, band, mode, frequency].joined(separator: "\u{001F}")
    }

    public var sha256: String {
        SHA256.hash(data: Data(canonicalString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizeCall(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func normalizeTimestamp(_ value: String) -> String {
        value
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .replacingOccurrences(of: " :", with: ":")
            .replacingOccurrences(of: ": ", with: ":")
    }

    private static func normalizeBand(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ",", with: ".")
    }

    private static func normalizeMode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func normalizeFrequency(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
    }
}
