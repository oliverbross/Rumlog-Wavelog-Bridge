import Foundation

public struct WavelogConfiguration: Sendable {
    public let baseURL: URL
    public let token: String
    public let stationID: Int

    public init(baseURL: URL, token: String, stationID: Int) throws {
        guard token.hasPrefix("wl2_") else {
            throw WavelogClientError.invalidConfiguration("A Wavelog API v2 token must start with wl2_.")
        }
        guard stationID > 0 else {
            throw WavelogClientError.invalidConfiguration("stationID must be positive.")
        }
        let host = baseURL.host?.lowercased()
        let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard baseURL.scheme?.lowercased() == "https" || (baseURL.scheme?.lowercased() == "http" && loopback) else {
            throw WavelogClientError.invalidConfiguration("Use HTTPS for Wavelog, except for loopback development URLs.")
        }
        self.baseURL = baseURL
        self.token = token
        self.stationID = stationID
    }
}

public enum WavelogClientError: Error, LocalizedError {
    case invalidConfiguration(String)
    case invalidURL
    case invalidResponse
    case rejected(status: Int, code: String?, message: String?)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message): return message
        case .invalidURL: return "Could not construct the Wavelog API URL."
        case .invalidResponse: return "Wavelog returned an invalid response."
        case let .rejected(status, code, message):
            return "Wavelog rejected the request (HTTP \(status), \(code ?? "unknown")): \(message ?? "no message")"
        }
    }
}

public struct WavelogQSO: Codable, Equatable, Sendable {
    public let id: Int
    public let stationID: Int?
    public let call: String
    public let band: String
    public let mode: String
    public let submode: String?
    // Wavelog API v2 serializes read-side frequencies as strings, even though
    // create and patch accept numeric Hz values.
    public let frequency: String?
    public let receiveFrequency: String?
    public let qsoDate: String
    public let rstSent: String?
    public let rstReceived: String?
    public let gridSquare: String?
    public let name: String?
    public let comment: String?
    public let notes: String?
    public let qth: String?

    enum CodingKeys: String, CodingKey {
        case id, call, band, mode, submode, name, comment, notes, qth
        case stationID = "station_id"
        case frequency = "freq"
        case receiveFrequency = "freq_rx"
        case qsoDate = "qso_date"
        case rstSent = "rst_sent"
        case rstReceived = "rst_rcvd"
        case gridSquare = "gridsquare"
    }
}

public struct WavelogListMeta: Codable, Equatable, Sendable {
    public let page: Int
    public let perPage: Int
    public let count: Int
    public let total: Int
    public let totalPages: Int
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case page, count, total
        case perPage = "per_page"
        case totalPages = "total_pages"
        case hasMore = "has_more"
    }
}

public struct WavelogQSOPage: Codable, Equatable, Sendable {
    public let data: [WavelogQSO]
    public let meta: WavelogListMeta
}

public struct WavelogQSOCreate: Codable, Equatable, Sendable {
    public let call: String
    public let band: String
    public let mode: String
    public let qsoDate: String
    public let timeOn: String
    public var frequency: Int64?
    public var rstSent: String?
    public var rstReceived: String?
    public var gridSquare: String?
    public var name: String?
    public var comment: String?
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case call, band, mode, name, comment, notes
        case qsoDate = "qso_date"
        case timeOn = "time_on"
        case frequency = "freq"
        case rstSent = "rst_sent"
        case rstReceived = "rst_rcvd"
        case gridSquare = "gridsquare"
    }

    public init(call: String, band: String, mode: String, qsoDate: String, timeOn: String) {
        self.call = call
        self.band = band
        self.mode = mode
        self.qsoDate = qsoDate
        self.timeOn = timeOn
    }
}

public struct WavelogQSOUpdate: Codable, Equatable, Sendable {
    public var call: String?
    public var band: String?
    public var mode: String?
    public var qsoDate: String?
    public var timeOn: String?
    public var frequency: Int64?
    public var rstSent: String?
    public var rstReceived: String?
    public var gridSquare: String?
    public var name: String?
    public var comment: String?
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case call, band, mode, name, comment, notes
        case qsoDate = "qso_date"
        case timeOn = "time_on"
        case frequency = "freq"
        case rstSent = "rst_sent"
        case rstReceived = "rst_rcvd"
        case gridSquare = "gridsquare"
    }

    public init() {}
}

private struct WavelogEnvelope<T: Codable & Sendable>: Codable, Sendable {
    let data: T?
    let error: WavelogAPIError?
}

private struct WavelogAPIError: Codable, Sendable {
    let code: String?
    let message: String?
}

private struct WavelogCreateBody: Encodable {
    let stationProfileID: Int
    let qso: WavelogQSOCreate

    enum CodingKeys: String, CodingKey {
        case call, band, mode, name, comment, notes
        case importType = "import_type"
        case stationProfileID = "station_profile_id"
        case qsoDate = "qso_date"
        case timeOn = "time_on"
        case frequency = "freq"
        case rstSent = "rst_sent"
        case rstReceived = "rst_rcvd"
        case gridSquare = "gridsquare"
    }

    init(stationProfileID: Int, qso: WavelogQSOCreate) {
        self.stationProfileID = stationProfileID
        self.qso = qso
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stationProfileID, forKey: .stationProfileID)
        try container.encode("json", forKey: .importType)
        try container.encode(qso.call, forKey: .call)
        try container.encode(qso.band, forKey: .band)
        try container.encode(qso.mode, forKey: .mode)
        try container.encode(qso.qsoDate, forKey: .qsoDate)
        try container.encode(qso.timeOn, forKey: .timeOn)
        try container.encodeIfPresent(qso.frequency, forKey: .frequency)
        try container.encodeIfPresent(qso.rstSent, forKey: .rstSent)
        try container.encodeIfPresent(qso.rstReceived, forKey: .rstReceived)
        try container.encodeIfPresent(qso.gridSquare, forKey: .gridSquare)
        try container.encodeIfPresent(qso.name, forKey: .name)
        try container.encodeIfPresent(qso.comment, forKey: .comment)
        try container.encodeIfPresent(qso.notes, forKey: .notes)
    }
}

public actor WavelogClient {
    private let configuration: WavelogConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(configuration: WavelogConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func listQSOs(page: Int = 1, perPage: Int = 500, sinceID: Int? = nil) async throws -> WavelogQSOPage {
        var items = [
            URLQueryItem(name: "station_id", value: String(configuration.stationID)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if let sinceID {
            items.append(URLQueryItem(name: "since_id", value: String(sinceID)))
        }
        let request = try makeRequest(method: "GET", qsoID: nil, queryItems: items, body: nil)
        let (data, response) = try await session.data(for: request)
        return try decodeDirect(WavelogQSOPage.self, data: data, response: response)
    }

    public func createQSO(_ qso: WavelogQSOCreate) async throws -> WavelogQSO {
        let body = try encoder.encode(WavelogCreateBody(stationProfileID: configuration.stationID, qso: qso))
        let request = try makeRequest(method: "POST", qsoID: nil, queryItems: [], body: body)
        let (data, response) = try await session.data(for: request)
        return try decodeEnvelope(WavelogQSO.self, data: data, response: response)
    }

    public func updateQSO(id: Int, fields: WavelogQSOUpdate) async throws -> WavelogQSO {
        let body = try encoder.encode(fields)
        let request = try makeRequest(method: "PATCH", qsoID: id, queryItems: [], body: body)
        let (data, response) = try await session.data(for: request)
        return try decodeEnvelope(WavelogQSO.self, data: data, response: response)
    }

    public func deleteQSO(id: Int) async throws {
        let request = try makeRequest(method: "DELETE", qsoID: id, queryItems: [], body: nil)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WavelogClientError.invalidResponse }
        guard http.statusCode == 204 else {
            throw WavelogClientError.rejected(status: http.statusCode, code: nil, message: nil)
        }
    }

    private func makeRequest(
        method: String,
        qsoID: Int?,
        queryItems: [URLQueryItem],
        body: Data?
    ) throws -> URLRequest {
        let root = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = qsoID.map { "/api/v2/qso/\($0)" } ?? "/api/v2/qso"
        guard var components = URLComponents(string: root + suffix) else { throw WavelogClientError.invalidURL }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw WavelogClientError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Rumlog-Wavelog-Bridge/0.1.0-dev", forHTTPHeaderField: "User-Agent")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func decodeDirect<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw WavelogClientError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw try rejection(data: data, status: http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func decodeEnvelope<T: Codable & Sendable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw WavelogClientError.invalidResponse }
        let envelope = try? decoder.decode(WavelogEnvelope<T>.self, from: data)
        guard 200..<300 ~= http.statusCode, let value = envelope?.data else {
            throw WavelogClientError.rejected(
                status: http.statusCode,
                code: envelope?.error?.code,
                message: envelope?.error?.message
            )
        }
        return value
    }

    private func rejection(data: Data, status: Int) throws -> WavelogClientError {
        let envelope = try? decoder.decode(WavelogEnvelope<WavelogQSO>.self, from: data)
        return .rejected(status: status, code: envelope?.error?.code, message: envelope?.error?.message)
    }
}
