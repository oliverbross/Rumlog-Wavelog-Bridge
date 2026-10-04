import BridgeCore
import Foundation

@main
struct BridgeRepairCommand {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RUN_REPAIR"] == "1" else {
            throw WavelogClientError.invalidConfiguration("Set RUN_REPAIR=1 to import audited-missing contacts into RUMlogNG.")
        }
        guard let token = environment["WAVELOG_TOKEN"], token.hasPrefix("wl2_") else {
            throw WavelogClientError.invalidConfiguration("WAVELOG_TOKEN must contain a v2 token.")
        }
        let baseURL = URL(string: environment["WAVELOG_URL"] ?? "https://om0rx.wavelog.online/index.php")!
        let stationID = Int(environment["WAVELOG_STATION_ID"] ?? "1") ?? 1
        let pageSize = Int(environment["WAVELOG_PAGE_SIZE"] ?? "5000") ?? 5_000
        let client = WavelogClient(configuration: try WavelogConfiguration(
            baseURL: baseURL,
            token: token,
            stationID: stationID
        ))

        var remoteRecords: [ADIFRecord] = []
        var pageNumber = 1
        while true {
            let page = try await client.exportADIF(page: pageNumber, perPage: pageSize)
            remoteRecords.append(contentsOf: ADIFParser().records(in: page.data.adif))
            if !page.meta.hasMore { break }
            pageNumber += 1
        }

        let rumlog = RumlogAppleEventClient()
        let localADIF = try await Task.detached {
            try rumlog.exportADIF(since: "1970-01-01 00:00:00")
        }.value
        let localHashes = Set(ADIFParser().records(in: localADIF).compactMap(\.semanticIdentityHash))
        var seenRemote = Set<String>()
        let missing = remoteRecords.filter { record in
            guard let hash = record.semanticIdentityHash, seenRemote.insert(hash).inserted else { return false }
            return !localHashes.contains(hash)
        }

        print("AUDITED_MISSING=\(missing.count)")
        for record in missing {
            try await Task.detached { try rumlog.importADIF(record.adifDocument) }.value
            print("REPAIR_SUBMITTED=\(record["CALL"] ?? "unknown")")
        }
        print("REPAIR_SUBMITTED_TOTAL=\(missing.count)")
    }
}
