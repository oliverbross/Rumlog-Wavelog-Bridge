import BridgeCore
import Foundation

@main
struct BridgeAuditCommand {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
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
        let localRecords = ADIFParser().records(in: localADIF)
        let remoteHashes = Set(remoteRecords.compactMap(\.semanticIdentityHash))
        let localHashes = Set(localRecords.compactMap(\.semanticIdentityHash))
        let missingHashes = remoteHashes.subtracting(localHashes)
        let extraHashes = localHashes.subtracting(remoteHashes)
        let remoteCoreKeys = Set(remoteRecords.compactMap(crossProviderIdentityKey))
        let localCoreKeys = Set(localRecords.compactMap(crossProviderIdentityKey))
        let missingCoreKeys = remoteCoreKeys.subtracting(localCoreKeys)
        let extraCoreKeys = localCoreKeys.subtracting(remoteCoreKeys)
        let remoteByCoreKey = Dictionary(
            remoteRecords.compactMap { record in crossProviderIdentityKey(record).map { ($0, record) } },
            uniquingKeysWith: { first, _ in first }
        )
        let localByCoarseKey = Dictionary(grouping: localRecords, by: coarseIdentityKey)
        let localByCallDateBand = Dictionary(grouping: localRecords, by: callDateBandKey)
        let localRumlogDuplicateKeys = Set(localRecords.compactMap(rumlogDuplicateKey))
        let remoteByHash = Dictionary(
            remoteRecords.compactMap { record in record.semanticIdentityHash.map { ($0, record) } },
            uniquingKeysWith: { first, _ in first }
        )
        let duplicateRuleCollisions = missingHashes.compactMap { remoteByHash[$0] }
            .filter { record in
                rumlogDuplicateKey(record).map(localRumlogDuplicateKeys.contains) ?? false
            }
        let samples = missingHashes.prefix(10).compactMap { hash -> String? in
            guard let record = remoteByHash[hash] else { return nil }
            return [record["CALL"], record["QSO_DATE"], record["TIME_ON"], record["BAND"], record["MODE"]]
                .compactMap { $0 }
                .joined(separator: " ")
        }

        print("WAVELOG_RECORDS=\(remoteRecords.count)")
        print("WAVELOG_UNIQUE=\(remoteHashes.count)")
        print("RUMLOG_RECORDS=\(localRecords.count)")
        print("RUMLOG_UNIQUE=\(localHashes.count)")
        print("MISSING_IN_RUMLOG=\(missingHashes.count)")
        print("EXTRA_IN_RUMLOG=\(extraHashes.count)")
        print("MISSING_MATCHING_RUMLOG_DUPLICATE_RULE=\(duplicateRuleCollisions.count)")
        print("WAVELOG_CORE_UNIQUE=\(remoteCoreKeys.count)")
        print("RUMLOG_CORE_UNIQUE=\(localCoreKeys.count)")
        print("CORE_MISSING_IN_RUMLOG=\(missingCoreKeys.count)")
        print("CORE_EXTRA_IN_RUMLOG=\(extraCoreKeys.count)")
        for sample in samples { print("MISSING_SAMPLE=\(sample)") }
        for key in missingCoreKeys.prefix(10) {
            guard let remote = remoteByCoreKey[key] else { continue }
            let exactTime = localByCoarseKey[coarseIdentityKey(remote)]?.first
            let nearest = localByCallDateBand[callDateBandKey(remote)]?.min { lhs, rhs in
                timeDistance(lhs, remote) < timeDistance(rhs, remote)
            }
            print("CORE_PAIR_REMOTE=\(describe(remote))")
            print("CORE_PAIR_LOCAL_EXACT_TIME=\(exactTime.map(describe) ?? "none")")
            print("CORE_PAIR_LOCAL_NEAREST=\(nearest.map(describe) ?? "none")")
        }
    }

    private static func coarseIdentityKey(_ record: ADIFRecord) -> String {
        [record["QSO_DATE"], record["TIME_ON"], record["BAND"]]
            .map { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .joined(separator: "|")
    }

    private static func callDateBandKey(_ record: ADIFRecord) -> String {
        [record["CALL"], record["QSO_DATE"], record["BAND"]]
            .map { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .joined(separator: "|")
    }

    private static func timeDistance(_ lhs: ADIFRecord, _ rhs: ADIFRecord) -> Int {
        abs(timeSeconds(lhs["TIME_ON"]) - timeSeconds(rhs["TIME_ON"]))
    }

    private static func timeSeconds(_ value: String?) -> Int {
        let digits = (value ?? "").filter(\.isNumber)
        guard digits.count >= 4 else { return Int.max / 4 }
        let hour = Int(digits.prefix(2)) ?? 0
        let minute = Int(digits.dropFirst(2).prefix(2)) ?? 0
        let second = digits.count >= 6 ? Int(digits.dropFirst(4).prefix(2)) ?? 0 : 0
        return hour * 3_600 + minute * 60 + second
    }

    private static func describe(_ record: ADIFRecord) -> String {
        ["CALL", "QSO_DATE", "TIME_ON", "QSO_DATE_OFF", "TIME_OFF", "BAND", "MODE", "SUBMODE", "FREQ"]
            .map { "\($0)=\(record[$0] ?? "")" }
            .joined(separator: " ")
    }

    private static func crossProviderIdentityKey(_ record: ADIFRecord) -> String? {
        guard
            let call = record["CALL"],
            let date = preferredDate(record),
            let time = preferredTime(record),
            let band = record["BAND"],
            let mode = nonEmpty(record["SUBMODE"]) ?? record["MODE"]
        else { return nil }
        return [call, date, time, band, mode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .joined(separator: "|")
    }

    private static func rumlogDuplicateKey(_ record: ADIFRecord) -> String? {
        guard
            let date = preferredDate(record),
            let time = preferredTime(record),
            let band = record["BAND"],
            let mode = nonEmpty(record["SUBMODE"]) ?? record["MODE"]
        else { return nil }
        return [date, time, band, mode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .joined(separator: "|")
    }

    private static func preferredDate(_ record: ADIFRecord) -> String? {
        nonEmpty(record["QSO_DATE_OFF"]) ?? record["QSO_DATE"]
    }

    private static func preferredTime(_ record: ADIFRecord) -> String? {
        nonEmpty(record["TIME_OFF"]) ?? record["TIME_ON"]
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
