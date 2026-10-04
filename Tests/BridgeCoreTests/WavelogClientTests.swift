import Foundation
import Testing
@testable import BridgeCore

@Test func createsWavelogQSOWithBearerTokenAndStation() async throws {
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: sessionConfiguration)

    MockURLProtocol.handler = { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/index.php/api/v2/qso")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer wl2_test_token")

        let body = try requestBody(request)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["station_profile_id"] as? Int == 7)
        #expect(json["import_type"] as? String == "json")
        #expect(json["call"] as? String == "N0TEST")
        #expect(json["qso_date"] as? String == "2026-10-04")

        let response = try #require(HTTPURLResponse(
            url: request.url!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        let data = Data("""
        {"data":{"id":42,"station_id":7,"call":"N0TEST","band":"20m","mode":"CW","submode":null,"freq":"14050000","freq_rx":null,"qso_date":"2026-10-04 08:00:00","rst_sent":"599","rst_rcvd":"599","gridsquare":"AA00","name":null,"comment":null,"notes":null,"qth":null},"error":null}
        """.utf8)
        return (response, data)
    }
    defer { MockURLProtocol.handler = nil }

    let configuration = try WavelogConfiguration(
        baseURL: URL(string: "http://127.0.0.1/index.php")!,
        token: "wl2_test_token",
        stationID: 7
    )
    let client = WavelogClient(configuration: configuration, session: session)
    var qso = WavelogQSOCreate(
        call: "N0TEST",
        band: "20m",
        mode: "CW",
        qsoDate: "2026-10-04",
        timeOn: "080000"
    )
    qso.frequency = 14_050_000
    qso.rstSent = "599"
    qso.rstReceived = "599"

    let created = try await client.createQSO(qso)
    #expect(created.id == 42)
    #expect(created.call == "N0TEST")
    #expect(created.frequency == "14050000")

    MockURLProtocol.handler = { request in
        let body = try requestBody(request)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["station_profile_id"] as? Int == 7)
        #expect(json["import_type"] as? String == "adif")
        #expect((json["adif"] as? String)?.contains("<CALL:6>N0TEST") == true)
        let response = try #require(HTTPURLResponse(
            url: request.url!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        return (response, Data("""
        {"data":{"parsed":1,"imported":1,"skipped":0,"messages":[]},"error":null}
        """.utf8))
    }
    let imported = try await client.importADIF("<EOH><CALL:6>N0TEST<EOR>")
    #expect(imported.imported == 1)

    MockURLProtocol.handler = { request in
        #expect(request.httpMethod == "GET")
        let response = try #require(HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        return (response, Data("""
        {"data":{"exported":0,"lastfetchedid":42,"adif":null},"meta":{"page":1,"per_page":500,"count":0,"total":0,"total_pages":0,"has_more":false}}
        """.utf8))
    }
    let empty = try await client.exportADIF(sinceID: 42)
    #expect(empty.data.exported == 0)
    #expect(empty.data.adif.isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_WAVELOG_DRYRUN"] == "1"))
func validatesLiveADIFWithoutWriting() async throws {
    let environment = ProcessInfo.processInfo.environment
    let token = try #require(environment["WAVELOG_TOKEN"])
    let baseURL = try #require(URL(string: environment["WAVELOG_URL"] ?? ""))
    let stationID = try #require(Int(environment["WAVELOG_STATION_ID"] ?? ""))
    let client = WavelogClient(configuration: try WavelogConfiguration(
        baseURL: baseURL,
        token: token,
        stationID: stationID
    ))
    let source = try await client.exportADIF(page: 1, perPage: 1)
    let result = try await client.validateADIF(source.data.adif)
    #expect(result.dryrun)
    #expect(result.parsed == 1)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_WAVELOG_DUPLICATE_WRITE"] == "1"))
func reconcilesLiveDuplicateADIFWithoutCreatingAnotherQSO() async throws {
    let environment = ProcessInfo.processInfo.environment
    let token = try #require(environment["WAVELOG_TOKEN"])
    let baseURL = try #require(URL(string: environment["WAVELOG_URL"] ?? ""))
    let stationID = try #require(Int(environment["WAVELOG_STATION_ID"] ?? ""))
    let client = WavelogClient(configuration: try WavelogConfiguration(
        baseURL: baseURL,
        token: token,
        stationID: stationID
    ))
    let before = try await client.exportADIF(page: 1, perPage: 1)
    let result = try await client.importADIF(before.data.adif)
    let after = try await client.exportADIF(page: 1, perPage: 1)

    #expect(result.parsed == 1)
    #expect(result.imported == 0)
    #expect(result.skipped == 1)
    #expect(after.meta.total == before.meta.total)
}

@Test func rejectsInsecureNonLoopbackWavelogURL() {
    #expect(throws: WavelogClientError.self) {
        try WavelogConfiguration(
            baseURL: URL(string: "http://wavelog.example/index.php")!,
            token: "wl2_test_token",
            stationID: 1
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}
