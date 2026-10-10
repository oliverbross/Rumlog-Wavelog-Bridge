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
    case writeVerificationFailed(id: Int)
    case rejected(status: Int, code: String?, message: String?)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message): return message
        case .invalidURL: return "Could not construct the Wavelog API URL."
        case .invalidResponse: return "Wavelog returned an invalid response."
        case let .writeVerificationFailed(id):
            return "Wavelog QSO \(id) did not match the requested edit after readback; the reconciliation baseline was not advanced."
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
    // Deployed Wavelog versions have returned both numeric and string JSON
    // representations. Decoding normalizes either representation to text.
    public let frequency: String?
    public let receiveFrequency: String?
    public let receiveBand: String?
    public let qsoDate: String
    public let rstSent: String?
    public let rstReceived: String?
    public let gridSquare: String?
    public let name: String?
    public let comment: String?
    public let notes: String?
    public let qth: String?
    public let state: String?
    public let county: String?
    public let iota: String?
    public let qslVia: String?
    public let power: String?
    public let cqZone: String?
    public let ituZone: String?
    public let propagationMode: String?
    public let satelliteName: String?
    public let satelliteMode: String?
    public let sotaReference: String?
    public let potaReference: String?
    public let wwffReference: String?

    enum CodingKeys: String, CodingKey {
        case id, call, band, mode, submode, name, comment, notes, qth, state, iota
        case stationID = "station_id"
        case frequency = "freq"
        case receiveFrequency = "freq_rx"
        case receiveBand = "band_rx"
        case qsoDate = "qso_date"
        case rstSent = "rst_sent"
        case rstReceived = "rst_rcvd"
        case gridSquare = "gridsquare"
        case county = "cnty"
        case qslVia = "qsl_via"
        case power = "tx_pwr"
        case cqZone = "cqz"
        case ituZone = "ituz"
        case propagationMode = "prop_mode"
        case satelliteName = "sat_name"
        case satelliteMode = "sat_mode"
        case sotaReference = "sota_ref"
        case potaReference = "pota_ref"
        case wwffReference = "wwff_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        stationID = try container.decodeIfPresent(Int.self, forKey: .stationID)
        call = try container.decode(String.self, forKey: .call)
        band = try container.decode(String.self, forKey: .band)
        mode = try container.decode(String.self, forKey: .mode)
        submode = try container.decodeIfPresent(String.self, forKey: .submode)
        frequency = try container.decodeFlexibleStringIfPresent(forKey: .frequency)
        receiveFrequency = try container.decodeFlexibleStringIfPresent(forKey: .receiveFrequency)
        receiveBand = try container.decodeIfPresent(String.self, forKey: .receiveBand)
        qsoDate = try container.decode(String.self, forKey: .qsoDate)
        rstSent = try container.decodeIfPresent(String.self, forKey: .rstSent)
        rstReceived = try container.decodeIfPresent(String.self, forKey: .rstReceived)
        gridSquare = try container.decodeIfPresent(String.self, forKey: .gridSquare)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        qth = try container.decodeIfPresent(String.self, forKey: .qth)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        county = try container.decodeIfPresent(String.self, forKey: .county)
        iota = try container.decodeIfPresent(String.self, forKey: .iota)
        qslVia = try container.decodeIfPresent(String.self, forKey: .qslVia)
        power = try container.decodeFlexibleStringIfPresent(forKey: .power)
        cqZone = try container.decodeFlexibleStringIfPresent(forKey: .cqZone)
        ituZone = try container.decodeFlexibleStringIfPresent(forKey: .ituZone)
        propagationMode = try container.decodeIfPresent(String.self, forKey: .propagationMode)
        satelliteName = try container.decodeIfPresent(String.self, forKey: .satelliteName)
        satelliteMode = try container.decodeIfPresent(String.self, forKey: .satelliteMode)
        sotaReference = try container.decodeIfPresent(String.self, forKey: .sotaReference)
        potaReference = try container.decodeIfPresent(String.self, forKey: .potaReference)
        wwffReference = try container.decodeIfPresent(String.self, forKey: .wwffReference)
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

public struct WavelogStation: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let uuid: String?
    public let name: String
    public let callsign: String
    public let gridsquare: String?
    public let city: String?
    public let country: String?
    public let active: Bool
}

public struct WavelogADIFData: Codable, Equatable, Sendable {
    public let exported: Int
    public let lastFetchedID: Int?
    public let adif: String

    enum CodingKeys: String, CodingKey {
        case exported, adif
        case lastFetchedID = "lastfetchedid"
    }

    public init(exported: Int, lastFetchedID: Int?, adif: String) {
        self.exported = exported
        self.lastFetchedID = lastFetchedID
        self.adif = adif
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exported = try container.decode(Int.self, forKey: .exported)
        lastFetchedID = try container.decodeIfPresent(Int.self, forKey: .lastFetchedID)
        adif = try container.decodeIfPresent(String.self, forKey: .adif) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exported, forKey: .exported)
        try container.encodeIfPresent(lastFetchedID, forKey: .lastFetchedID)
        try container.encode(adif, forKey: .adif)
    }
}

public struct WavelogADIFPage: Codable, Equatable, Sendable {
    public let data: WavelogADIFData
    public let meta: WavelogListMeta
}

public struct WavelogImportSummary: Codable, Equatable, Sendable {
    public let parsed: Int
    public let imported: Int
    public let skipped: Int
    public let messages: [String]
}

public struct WavelogADIFValidation: Codable, Equatable, Sendable {
    public let dryrun: Bool
    public let parsed: Int
}

public struct WavelogQSOCreate: Codable, Equatable, Sendable {
    public let call: String
    public let band: String
    public let mode: String
    public let qsoDate: String
    public let timeOn: String
    public var frequency: Int64?
    public var receiveFrequency: Int64?
    public var receiveBand: String?
    public var rstSent: String?
    public var rstReceived: String?
    public var gridSquare: String?
    public var name: String?
    public var comment: String?
    public var notes: String?
    public var qth: String?
    public var state: String?
    public var county: String?
    public var iota: String?
    public var qslVia: String?
    public var power: String?
    public var cqZone: String?
    public var ituZone: String?
    public var propagationMode: String?
    public var satelliteName: String?
    public var satelliteMode: String?
    public var sotaReference: String?
    public var potaReference: String?
    public var wwffReference: String?

    enum CodingKeys: String, CodingKey {
        case call, band, mode, name, comment, notes, qth, state, iota
        case qsoDate = "qso_date"
        case timeOn = "time_on"
        case frequency = "freq"
        case receiveFrequency = "freq_rx"
        case receiveBand = "band_rx"
        case rstSent = "rst_sent"
        case rstReceived = "rst_rcvd"
        case gridSquare = "gridsquare"
        case county = "cnty"
        case qslVia = "qsl_via"
        case power = "tx_pwr"
        case cqZone = "cqz"
        case ituZone = "ituz"
        case propagationMode = "prop_mode"
        case satelliteName = "sat_name"
        case satelliteMode = "sat_mode"
        case sotaReference = "sota_ref"
        case potaReference = "pota_ref"
        case wwffReference = "wwff_ref"
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
    public var receiveBand: String?
    public var rstSent: String?
    public var rstReceived: String?
    public var gridSquare: String?
    public var name: String?
    public var comment: String?
    public var notes: String?
    public var qth: String?
    public var state: String?
    public var county: String?
    public var iota: String?
    public var qslVia: String?
    public var power: String?
    public var cqZone: String?
    public var ituZone: String?
    public var propagationMode: String?
    public var satelliteName: String?
    public var satelliteMode: String?
    public var sotaReference: String?
    public var potaReference: String?
    public var wwffReference: String?

    enum CodingKeys: String, CodingKey {
        case call, band, mode, name, comment, notes, qth, state, iota
        case qsoDate = "qso_date"
        case timeOn = "time_on"
        case frequency = "freq"
        case receiveBand = "band_rx"
        case rstSent = "rst_sent"
        case rstReceived = "rst_rcvd"
        case gridSquare = "gridsquare"
        case county = "cnty"
        case qslVia = "qsl_via"
        case power = "tx_pwr"
        case cqZone = "cqz"
        case ituZone = "ituz"
        case propagationMode = "prop_mode"
        case satelliteName = "sat_name"
        case satelliteMode = "sat_mode"
        case sotaReference = "sota_ref"
        case potaReference = "pota_ref"
        case wwffReference = "wwff_ref"
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

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Decimal.self, forKey: key) {
            return NSDecimalNumber(decimal: value).stringValue
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected a JSON string or number."
            )
        )
    }
}

private struct WavelogCreateBody: Encodable {
    let stationProfileID: Int
    let qso: WavelogQSOCreate

    enum CodingKeys: String, CodingKey {
        case call, band, mode, name, comment, notes, qth, state, iota
        case importType = "import_type"
        case stationProfileID = "station_profile_id"
        case qsoDate = "qso_date"
        case timeOn = "time_on"
        case frequency = "freq"
        case receiveFrequency = "freq_rx"
        case receiveBand = "band_rx"
        case rstSent = "rst_sent"
        case rstReceived = "rst_rcvd"
        case gridSquare = "gridsquare"
        case county = "cnty"
        case qslVia = "qsl_via"
        case power = "tx_pwr"
        case cqZone = "cqz"
        case ituZone = "ituz"
        case propagationMode = "prop_mode"
        case satelliteName = "sat_name"
        case satelliteMode = "sat_mode"
        case sotaReference = "sota_ref"
        case potaReference = "pota_ref"
        case wwffReference = "wwff_ref"
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
        try container.encodeIfPresent(qso.receiveFrequency, forKey: .receiveFrequency)
        try container.encodeIfPresent(qso.receiveBand, forKey: .receiveBand)
        try container.encodeIfPresent(qso.rstSent, forKey: .rstSent)
        try container.encodeIfPresent(qso.rstReceived, forKey: .rstReceived)
        try container.encodeIfPresent(qso.gridSquare, forKey: .gridSquare)
        try container.encodeIfPresent(qso.name, forKey: .name)
        try container.encodeIfPresent(qso.comment, forKey: .comment)
        try container.encodeIfPresent(qso.notes, forKey: .notes)
        try container.encodeIfPresent(qso.qth, forKey: .qth)
        try container.encodeIfPresent(qso.state, forKey: .state)
        try container.encodeIfPresent(qso.county, forKey: .county)
        try container.encodeIfPresent(qso.iota, forKey: .iota)
        try container.encodeIfPresent(qso.qslVia, forKey: .qslVia)
        try container.encodeIfPresent(qso.power, forKey: .power)
        try container.encodeIfPresent(qso.cqZone, forKey: .cqZone)
        try container.encodeIfPresent(qso.ituZone, forKey: .ituZone)
        try container.encodeIfPresent(qso.propagationMode, forKey: .propagationMode)
        try container.encodeIfPresent(qso.satelliteName, forKey: .satelliteName)
        try container.encodeIfPresent(qso.satelliteMode, forKey: .satelliteMode)
        try container.encodeIfPresent(qso.sotaReference, forKey: .sotaReference)
        try container.encodeIfPresent(qso.potaReference, forKey: .potaReference)
        try container.encodeIfPresent(qso.wwffReference, forKey: .wwffReference)
    }
}

private struct WavelogADIFImportBody: Encodable {
    let stationProfileID: Int
    let importType = "adif"
    let adif: String
    let dryrun: Bool?

    enum CodingKeys: String, CodingKey {
        case adif, dryrun
        case stationProfileID = "station_profile_id"
        case importType = "import_type"
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
        let request = try makeRequest(method: "GET", resourceID: nil, queryItems: items, body: nil)
        let (data, response) = try await session.data(for: request)
        return try decodeDirect(WavelogQSOPage.self, data: data, response: response)
    }

    public func getQSO(id: Int) async throws -> WavelogQSO {
        let request = try makeRequest(method: "GET", resourceID: id, queryItems: [], body: nil)
        let (data, response) = try await session.data(for: request)
        return try decodeEnvelope(WavelogQSO.self, data: data, response: response)
    }

    public func listStations() async throws -> [WavelogStation] {
        let request = try makeRequest(method: "GET", resource: "station", resourceID: nil, queryItems: [], body: nil)
        let (data, response) = try await session.data(for: request)
        return try decodeEnvelope([WavelogStation].self, data: data, response: response)
    }

    public func exportADIF(page: Int = 1, perPage: Int = 500, sinceID: Int? = nil) async throws -> WavelogADIFPage {
        var items = [
            URLQueryItem(name: "format", value: "adif"),
            URLQueryItem(name: "station_id", value: String(configuration.stationID)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if let sinceID { items.append(URLQueryItem(name: "since_id", value: String(sinceID))) }
        let request = try makeRequest(method: "GET", resource: "qso", resourceID: nil, queryItems: items, body: nil)
        let (data, response) = try await session.data(for: request)
        return try decodeDirect(WavelogADIFPage.self, data: data, response: response)
    }

    public func createQSO(_ qso: WavelogQSOCreate) async throws -> WavelogQSO {
        let body = try encoder.encode(WavelogCreateBody(stationProfileID: configuration.stationID, qso: qso))
        let request = try makeRequest(method: "POST", resourceID: nil, queryItems: [], body: body)
        let (data, response) = try await session.data(for: request)
        return try decodeEnvelope(WavelogQSO.self, data: data, response: response)
    }

    public func importADIF(_ adif: String) async throws -> WavelogImportSummary {
        let body = try encoder.encode(WavelogADIFImportBody(
            stationProfileID: configuration.stationID,
            adif: adif,
            dryrun: nil
        ))
        let request = try makeRequest(method: "POST", resourceID: nil, queryItems: [], body: body)
        let (data, response) = try await session.data(for: request)
        return try decodeEnvelope(WavelogImportSummary.self, data: data, response: response)
    }

    public func validateADIF(_ adif: String) async throws -> WavelogADIFValidation {
        let body = try encoder.encode(WavelogADIFImportBody(
            stationProfileID: configuration.stationID,
            adif: adif,
            dryrun: true
        ))
        let request = try makeRequest(method: "POST", resourceID: nil, queryItems: [], body: body)
        let (data, response) = try await session.data(for: request)
        return try decodeEnvelope(WavelogADIFValidation.self, data: data, response: response)
    }

    public func updateQSO(id: Int, fields: WavelogQSOUpdate) async throws -> WavelogQSO {
        let body = try encoder.encode(fields)
        let request = try makeRequest(method: "PATCH", resourceID: id, queryItems: [], body: body)
        let (data, response) = try await session.data(for: request)
        return try decodeEnvelope(WavelogQSO.self, data: data, response: response)
    }

    public func deleteQSO(id: Int) async throws {
        let request = try makeRequest(method: "DELETE", resourceID: id, queryItems: [], body: nil)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WavelogClientError.invalidResponse }
        guard http.statusCode == 204 else {
            throw WavelogClientError.rejected(status: http.statusCode, code: nil, message: nil)
        }
    }

    private func makeRequest(
        method: String,
        resource: String = "qso",
        resourceID: Int?,
        queryItems: [URLQueryItem],
        body: Data?
    ) throws -> URLRequest {
        let root = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = resourceID.map { "/api/v2/\(resource)/\($0)" } ?? "/api/v2/\(resource)"
        guard var components = URLComponents(string: root + suffix) else { throw WavelogClientError.invalidURL }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw WavelogClientError.invalidURL }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("OM0RX-xBridge/0.3.0", forHTTPHeaderField: "User-Agent")
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
