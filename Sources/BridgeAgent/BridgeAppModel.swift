import BridgeCore
import Foundation

@MainActor
final class BridgeAppModel: ObservableObject {
    @Published var settings = BridgeSettings()
    @Published var token = ""
    @Published var stations: [WavelogStation] = []
    @Published var status = "Loading settings…"
    @Published var detail = ""
    @Published var isBusy = false
    @Published private(set) var isBootstrapping = false
    @Published var rumlogInstalled = false
    @Published var rumlogRunning = false
    @Published var rumlogInstanceCount = 0
    @Published var bootstrap = BootstrapState(stationID: 1)
    @Published var syncState = ContinuousSyncState(stationID: 1)

    private var fileStore: BridgeFileStore?
    private var ledger: SyncLedger?
    private let keychain = KeychainTokenStore()
    private var bootstrapTask: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?

    init() {
        Task { await load() }
    }

    var canConnect: Bool {
        !token.isEmpty && URL(string: settings.wavelogBaseURL) != nil && !isBusy
    }

    var canBootstrap: Bool {
        canConnect && rumlogInstanceCount == 1 && !bootstrap.completed
    }

    var canLiveSync: Bool {
        canConnect && rumlogInstanceCount == 1 && bootstrap.completed && !isBusy
    }

    func load() async {
        do {
            let store = try BridgeFileStore()
            fileStore = store
            settings = try await store.loadSettings()
            token = try keychain.load() ?? ""
            bootstrap = try await store.loadBootstrapState(stationID: settings.stationID)
            syncState = try await store.loadContinuousSyncState(stationID: settings.stationID)
            ledger = try SyncLedger(fileURL: await store.ledgerURL())
            refreshRumlogState()
            status = token.isEmpty ? "Add the Wavelog API v2 token." : "Ready to test connections."
            scheduleAutomaticSync()
        } catch {
            status = "Could not load settings"
            detail = error.localizedDescription
        }
    }

    func saveAndConnect() {
        Task {
            await perform("Connecting to Wavelog…") {
                try self.validateInput()
                try self.keychain.save(self.token)
                try await self.fileStore?.saveSettings(self.settings)
                let discovered = try await self.makeWavelogClient().listStations()
                self.stations = discovered
                if let selected = discovered.first(where: { $0.id == self.settings.stationID })
                    ?? discovered.first(where: \.active)
                    ?? discovered.first {
                    self.settings.stationID = selected.id
                    self.settings.stationName = selected.name
                    try await self.fileStore?.saveSettings(self.settings)
                    self.bootstrap = try await self.fileStore?.loadBootstrapState(stationID: selected.id)
                        ?? BootstrapState(stationID: selected.id)
                    self.syncState = try await self.fileStore?.loadContinuousSyncState(stationID: selected.id)
                        ?? ContinuousSyncState(stationID: selected.id)
                }
                self.status = "Connected"
                self.detail = "Wavelog API v2 accepted the token and returned \(discovered.count) station profile(s)."
            }
        }
    }

    func chooseStation(_ id: Int) {
        guard let station = stations.first(where: { $0.id == id }) else { return }
        settings.stationID = station.id
        settings.stationName = station.name
        Task {
            try? await fileStore?.saveSettings(settings)
            bootstrap = (try? await fileStore?.loadBootstrapState(stationID: id))
                ?? BootstrapState(stationID: id)
            syncState = (try? await fileStore?.loadContinuousSyncState(stationID: id))
                ?? ContinuousSyncState(stationID: id)
        }
    }

    func testRumlog() {
        Task {
            await perform("Testing RUMlogNG…") {
                self.refreshRumlogState()
                try await self.fileStore?.saveSettings(self.settings)
                let client = RumlogAppleEventClient(bundleIdentifier: self.settings.rumlogBundleIdentifier)
                _ = try await Task.detached {
                    try client.exportADIF(since: "2099-01-01 00:00:00")
                }.value
                self.status = "RUMlogNG connected"
                self.detail = "Apple Events are available for the open logbook."
            }
        }
    }

    func startBootstrap() {
        guard bootstrapTask == nil else { return }
        isBootstrapping = true
        bootstrapTask = Task {
            await perform("Preparing bootstrap…") {
                let wavelog = try self.makeWavelogClient()
                let rumlog = RumlogAppleEventClient(bundleIdentifier: self.settings.rumlogBundleIdentifier)
                let bootstrapStartedAt = Date()
                var state = try await self.fileStore?.loadBootstrapState(stationID: self.settings.stationID)
                    ?? BootstrapState(stationID: self.settings.stationID)
                var continuous = try await self.fileStore?.loadContinuousSyncState(stationID: self.settings.stationID)
                    ?? ContinuousSyncState(stationID: self.settings.stationID)

                let existingADIF = try await Task.detached {
                    try rumlog.exportADIF(since: "1970-01-01 00:00:00")
                }.value
                for record in ADIFParser().records(in: existingADIF) {
                    if let fingerprint = record.semanticIdentityHash {
                        continuous.knownFingerprints.insert(fingerprint)
                    }
                }

                while !Task.isCancelled {
                    let resumeID = state.lastFetchedID
                    let page = try await wavelog.exportADIF(
                        page: resumeID == nil ? state.nextPage : 1,
                        perPage: self.settings.bootstrapPageSize,
                        sinceID: resumeID
                    )
                    if state.totalCount == 0 { state.totalCount = page.meta.total }
                    if page.data.exported == 0 {
                        state.completed = true
                        state.updatedAt = Date()
                        try await self.fileStore?.saveBootstrapState(state)
                        self.bootstrap = state
                        break
                    }
                    self.status = "Importing contacts into RUMlogNG"
                    self.detail = "Batch \(state.nextPage) · \(state.importedCount) of \(state.totalCount) Wavelog records processed"
                    let filtered = ADIFParser().removingKnownRecords(
                        from: page.data.adif,
                        knownFingerprints: continuous.knownFingerprints
                    )
                    if !filtered.records.isEmpty {
                        try await Task.detached {
                            try rumlog.importADIF(filtered.adif)
                        }.value
                    }
                    for record in ADIFParser().records(in: page.data.adif) {
                        if let fingerprint = record.semanticIdentityHash {
                            continuous.knownFingerprints.insert(fingerprint)
                        }
                    }
                    state.importedCount += page.data.exported
                    state.lastFetchedID = page.data.lastFetchedID
                    continuous.lastWavelogID = page.data.lastFetchedID
                    state.nextPage += 1
                    state.completed = !page.meta.hasMore
                    state.updatedAt = Date()
                    try await self.fileStore?.saveBootstrapState(state)
                    try await self.fileStore?.saveContinuousSyncState(continuous)
                    self.bootstrap = state
                    self.syncState = continuous
                    if state.completed { break }
                }

                if Task.isCancelled {
                    self.status = "Bootstrap paused"
                    self.detail = "Progress is saved; Resume continues at page \(state.nextPage)."
                } else {
                    if continuous.lastRumlogScanAt == nil {
                        continuous.lastRumlogScanAt = bootstrapStartedAt
                    }
                    continuous.lastSuccessAt = Date()
                    try await self.fileStore?.saveContinuousSyncState(continuous)
                    self.syncState = continuous
                    self.status = "Bootstrap complete"
                    self.detail = "Processed \(state.importedCount) Wavelog records. RUMlog duplicate rules may skip collisions; no deletion propagation was performed."
                }
            }
            self.bootstrapTask = nil
            self.isBootstrapping = false
        }
    }

    func pauseBootstrap() {
        bootstrapTask?.cancel()
    }

    func syncNow() {
        Task {
            await perform("Synchronizing new contacts…") {
                let result = try await self.runContinuousSync()
                self.status = "Sync complete"
                self.detail = "\(result.fromWavelog) checked from Wavelog · \(result.toWavelog) uploaded to Wavelog"
            }
        }
    }

    func setAutomaticSync(_ enabled: Bool) {
        settings.automaticSync = enabled
        Task {
            try? await fileStore?.saveSettings(settings)
            scheduleAutomaticSync()
        }
    }

    func setPollInterval(_ seconds: Int) {
        settings.pollIntervalSeconds = seconds
        Task {
            try? await fileStore?.saveSettings(settings)
            scheduleAutomaticSync()
        }
    }

    private func runContinuousSync() async throws -> (fromWavelog: Int, toWavelog: Int) {
        guard bootstrap.completed else {
            throw WavelogClientError.invalidConfiguration("Complete the initial bootstrap before enabling two-way live sync.")
        }
        let wavelog = try makeWavelogClient()
        let rumlog = RumlogAppleEventClient(bundleIdentifier: settings.rumlogBundleIdentifier)
        var state = try await fileStore?.loadContinuousSyncState(stationID: settings.stationID)
            ?? ContinuousSyncState(stationID: settings.stationID)
        var received = 0
        var sent = 0
        let scanStarted = Date()
        let localRecords: [ADIFRecord]
        if let previousScan = state.lastRumlogScanAt {
            let since = Self.sqlDateFormatter.string(from: previousScan.addingTimeInterval(-300))
            let localADIF = try await Task.detached { try rumlog.exportADIF(since: since) }.value
            localRecords = ADIFParser().records(in: localADIF)
        } else {
            localRecords = []
        }
        let recentLocalFingerprints = Set(localRecords.compactMap(\.semanticIdentityHash))
        var recoveryFingerprints: Set<String> = []
        if state.pendingInboundFingerprints != nil {
            let fullADIF = try await Task.detached {
                try rumlog.exportADIF(since: "1970-01-01 00:00:00")
            }.value
            recoveryFingerprints = Set(ADIFParser().records(in: fullADIF).compactMap(\.semanticIdentityHash))
        }

        while true {
            let page = try await wavelog.exportADIF(
                page: 1,
                perPage: settings.bootstrapPageSize,
                sinceID: state.lastWavelogID
            )
            guard page.data.exported > 0 else { break }
            let filtered = ADIFParser().removingKnownRecords(
                from: page.data.adif,
                knownFingerprints: state.knownFingerprints
                    .union(recentLocalFingerprints)
                    .union(recoveryFingerprints)
            )
            let inboundFingerprints = Set(
                ADIFParser().records(in: page.data.adif).compactMap(\.semanticIdentityHash)
            )
            state.pendingInboundFingerprints = inboundFingerprints
            try await fileStore?.saveContinuousSyncState(state)
            if !filtered.records.isEmpty {
                try await Task.detached { try rumlog.importADIF(filtered.adif) }.value
            }
            for record in ADIFParser().records(in: page.data.adif) {
                if let fingerprint = record.semanticIdentityHash {
                    state.knownFingerprints.insert(fingerprint)
                }
            }
            received += page.data.exported
            state.lastWavelogID = page.data.lastFetchedID
            state.pendingInboundFingerprints = nil
            try await fileStore?.saveContinuousSyncState(state)
            if !page.meta.hasMore { break }
        }

        if state.lastRumlogScanAt != nil {
            for record in localRecords {
                guard
                    let fingerprint = record.semanticIdentityHash,
                    !state.knownFingerprints.contains(fingerprint),
                    !record.adifDocument.isEmpty
                else { continue }

                let operation = PendingOperation(
                    direction: .rumlogToWavelog,
                    kind: .create,
                    rumlogID: fingerprint,
                    payloadHash: fingerprint
                )
                let operationID = try await ledger?.enqueue(operation) ?? operation.id
                try await ledger?.mark(
                    operationID: operationID,
                    state: .deliveryUnknown,
                    incrementAttempts: true
                )
                let summary = try await wavelog.importADIF(record.adifDocument)
                guard summary.imported + summary.skipped >= 1 else {
                    throw WavelogClientError.invalidResponse
                }
                try await ledger?.mark(operationID: operationID, state: .delivered)
                try await ledger?.upsert(ContactLink(
                    rumlogID: fingerprint,
                    semanticIdentityHash: fingerprint,
                    lastSeenInRumlog: Date(),
                    lastSeenInWavelog: Date()
                ))
                state.knownFingerprints.insert(fingerprint)
                sent += 1
                try await fileStore?.saveContinuousSyncState(state)
            }
        }

        state.lastRumlogScanAt = scanStarted
        state.lastSuccessAt = Date()
        try await fileStore?.saveContinuousSyncState(state)
        syncState = state
        return (received, sent)
    }

    private func scheduleAutomaticSync() {
        automaticTask?.cancel()
        automaticTask = nil
        guard settings.automaticSync else { return }
        automaticTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(max(settings.pollIntervalSeconds, 15)))
                } catch { break }
                guard !Task.isCancelled, !isBusy, bootstrap.completed else { continue }
                await perform("Automatic sync…") {
                    let result = try await self.runContinuousSync()
                    self.status = "Automatic sync complete"
                    self.detail = "\(result.fromWavelog) Wavelog rows checked · \(result.toWavelog) uploaded"
                }
            }
        }
    }

    private static let sqlDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private func refreshRumlogState() {
        let rumlog = RumlogAppleEventClient(bundleIdentifier: settings.rumlogBundleIdentifier)
        rumlogInstalled = rumlog.isInstalled()
        rumlogInstanceCount = rumlog.runningInstanceCount()
        rumlogRunning = rumlogInstanceCount > 0
    }

    private func validateInput() throws {
        guard token.hasPrefix("wl2_") else {
            throw WavelogClientError.invalidConfiguration("Enter a Wavelog API v2 token beginning with wl2_.")
        }
        guard let url = URL(string: settings.wavelogBaseURL) else {
            throw WavelogClientError.invalidConfiguration("Enter a valid Wavelog URL.")
        }
        _ = try WavelogConfiguration(baseURL: url, token: token, stationID: max(settings.stationID, 1))
    }

    private func makeWavelogClient() throws -> WavelogClient {
        try validateInput()
        return WavelogClient(configuration: try WavelogConfiguration(
            baseURL: URL(string: settings.wavelogBaseURL)!,
            token: token,
            stationID: settings.stationID
        ))
    }

    private func perform(
        _ initialStatus: String,
        operation: @escaping @MainActor () async throws -> Void
    ) async {
        isBusy = true
        status = initialStatus
        detail = ""
        do {
            try await operation()
        } catch is CancellationError {
            status = "Paused"
        } catch {
            status = "Action failed"
            detail = error.localizedDescription
        }
        isBusy = false
    }
}
