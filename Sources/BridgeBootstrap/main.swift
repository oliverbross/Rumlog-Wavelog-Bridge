import BridgeCore
import Foundation

@main
struct BridgeBootstrapCommand {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["WAVELOG_TOKEN"], token.hasPrefix("wl2_") else {
            throw WavelogClientError.invalidConfiguration("WAVELOG_TOKEN must contain a v2 token.")
        }
        let baseURL = URL(string: environment["WAVELOG_URL"] ?? "https://om0rx.wavelog.online/index.php")!
        let stationID = Int(environment["WAVELOG_STATION_ID"] ?? "1") ?? 1
        let pageSize = Int(environment["WAVELOG_PAGE_SIZE"] ?? "500") ?? 500
        let fileStore = try BridgeFileStore()
        var settings = try await fileStore.loadSettings()
        settings.wavelogBaseURL = baseURL.absoluteString
        settings.stationID = stationID
        try await fileStore.saveSettings(settings)

        let wavelog = WavelogClient(configuration: try WavelogConfiguration(
            baseURL: baseURL,
            token: token,
            stationID: stationID
        ))
        let stations = try await wavelog.listStations()
        guard let station = stations.first(where: { $0.id == stationID }) else {
            throw WavelogClientError.invalidConfiguration("Station #\(stationID) was not returned by Wavelog.")
        }
        settings.stationName = station.name
        try await fileStore.saveSettings(settings)

        let rumlog = RumlogAppleEventClient(bundleIdentifier: settings.rumlogBundleIdentifier)
        guard rumlog.isRunning() else { throw RumlogAppleEventError.notRunning }
        guard rumlog.runningInstanceCount() == 1 else {
            throw RumlogAppleEventError.multipleInstances(rumlog.runningInstanceCount())
        }
        let bootstrapStartedAt = Date()
        var bootstrap = try await fileStore.loadBootstrapState(stationID: stationID)
        var continuous = try await fileStore.loadContinuousSyncState(stationID: stationID)

        let existingADIF = try await Task.detached {
            try rumlog.exportADIF(since: "1970-01-01 00:00:00")
        }.value
        let existingFingerprints = Set(
            ADIFParser().records(in: existingADIF).compactMap(\.semanticIdentityHash)
        )
        if bootstrap.completed {
            continuous.knownFingerprints = existingFingerprints
        } else {
            continuous.knownFingerprints.formUnion(existingFingerprints)
        }

        print("CONNECTED station=\(station.id) name=\(station.name) callsign=\(station.callsign) existing=\(continuous.knownFingerprints.count)")
        while !bootstrap.completed {
            let resumeID = bootstrap.lastFetchedID
            let page = try await wavelog.exportADIF(
                page: resumeID == nil ? bootstrap.nextPage : 1,
                perPage: pageSize,
                sinceID: resumeID
            )
            if bootstrap.totalCount == 0 { bootstrap.totalCount = page.meta.total }
            if page.data.exported == 0 {
                bootstrap.completed = true
                break
            }
            let filtered = ADIFParser().removingKnownRecords(
                from: page.data.adif,
                knownFingerprints: continuous.knownFingerprints
            )
            if !filtered.records.isEmpty {
                try await Task.detached { try rumlog.importADIF(filtered.adif) }.value
            }
            for record in ADIFParser().records(in: page.data.adif) {
                if let fingerprint = record.semanticIdentityHash {
                    continuous.knownFingerprints.insert(fingerprint)
                }
            }
            bootstrap.importedCount += page.data.exported
            bootstrap.lastFetchedID = page.data.lastFetchedID
            bootstrap.nextPage += 1
            bootstrap.completed = !page.meta.hasMore
            bootstrap.updatedAt = Date()
            continuous.lastWavelogID = page.data.lastFetchedID
            try await fileStore.saveBootstrapState(bootstrap)
            try await fileStore.saveContinuousSyncState(continuous)
            print("PROGRESS processed=\(bootstrap.importedCount) total=\(bootstrap.totalCount) batch=\(bootstrap.nextPage - 1) new=\(filtered.records.count)")
        }

        continuous.lastRumlogScanAt = continuous.lastRumlogScanAt ?? bootstrapStartedAt
        continuous.lastSuccessAt = Date()
        settings.automaticSync = true
        try await fileStore.saveBootstrapState(bootstrap)
        try await fileStore.saveContinuousSyncState(continuous)
        try await fileStore.saveSettings(settings)
        print("COMPLETE processed=\(bootstrap.importedCount) total=\(bootstrap.totalCount) last_id=\(continuous.lastWavelogID ?? 0)")
    }
}
