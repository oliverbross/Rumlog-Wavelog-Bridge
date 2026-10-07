import BridgeCore
import AppKit
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
    @Published var rumlogPeerConnected = false
    @Published var rumlogPeerStatus = "Peer service is starting…"
    @Published var bootstrap = BootstrapState(stationID: 1)
    @Published var syncState = ContinuousSyncState(stationID: 1)

    private var fileStore: BridgeFileStore?
    private var ledger: SyncLedger?
    private let keychain = KeychainTokenStore()
    private var bootstrapTask: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var peerBridge: RumlogPeerBridge?
    private var reconciliationState: ReconciliationState?
    private var lastReconciliationAt: Date?
    private var lastReconciliationAttemptAt: Date?
    private var lastValidatedLogbookPath: String?
    private var lastLogbookValidationAt: Date?
    private let logbookValidationCacheSeconds: TimeInterval = 300
    private let reconciliationIntervalSeconds: TimeInterval = 300
    private let startupReconciliationDelaySeconds: TimeInterval = 300
    private let automaticInitialDelaySeconds: TimeInterval = 5
    private let incrementalRecoveryRowCount: Int64 = 1_000
    private var reconciliationNotBefore = Date.distantPast

    init() {
        Task { await load() }
    }

    var canConnect: Bool {
        !token.isEmpty && URL(string: settings.wavelogBaseURL) != nil && !isBusy
    }

    var canBootstrap: Bool {
        canConnect && rumlogInstanceCount == 1 && settings.rumlogLogbookPath?.isEmpty == false && !bootstrap.completed
    }

    var canLiveSync: Bool {
        canConnect && rumlogInstanceCount == 1 && settings.rumlogLogbookPath?.isEmpty == false
            && bootstrap.completed && !isBusy
    }

    func load() async {
        do {
            let store = try BridgeFileStore()
            fileStore = store
            settings = try await store.loadSettings()
            token = try keychain.load() ?? ""
            bootstrap = try await store.loadBootstrapState(stationID: settings.stationID)
            syncState = try await store.loadContinuousSyncState(stationID: settings.stationID)
            reconciliationState = try await store.loadReconciliationState(stationID: settings.stationID)
            lastReconciliationAt = syncState.lastReconciliationAt ?? reconciliationState?.lastRunAt
            lastReconciliationAttemptAt = lastReconciliationAt
            reconciliationNotBefore = Date().addingTimeInterval(startupReconciliationDelaySeconds)
            ledger = try SyncLedger(fileURL: await store.ledgerURL())
            refreshRumlogState()
            startPeerBridge()
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
                    self.reconciliationState = try await self.fileStore?.loadReconciliationState(stationID: selected.id)
                        ?? ReconciliationState(stationID: selected.id)
                    self.lastReconciliationAt = self.syncState.lastReconciliationAt
                        ?? self.reconciliationState?.lastRunAt
                    self.lastReconciliationAttemptAt = self.lastReconciliationAt
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
            reconciliationState = (try? await fileStore?.loadReconciliationState(stationID: id))
                ?? ReconciliationState(stationID: id)
            lastReconciliationAt = syncState.lastReconciliationAt ?? reconciliationState?.lastRunAt
            lastReconciliationAttemptAt = lastReconciliationAt
        }
    }

    func testRumlog() {
        Task {
            await perform("Testing RUMlogNG…") {
                self.refreshRumlogState()
                try await self.fileStore?.saveSettings(self.settings)
                if let path = self.settings.rumlogLogbookPath, !path.isEmpty {
                    let count = try await Task.detached {
                        try RumlogSQLiteReader(fileURL: URL(fileURLWithPath: path)).count()
                    }.value
                    try await self.validateOpenLogbook(force: true)
                    self.detail = "Apple Events are available and the selected read-only logbook contains \(count.formatted()) contacts. Its latest QSO matches the logbook open in RUMlogNG."
                } else {
                    throw WavelogClientError.invalidConfiguration("Choose the .rlog file currently open in RUMlogNG.")
                }
                self.startPeerBridge()
                self.status = "RUMlogNG connected"
                if self.detail.isEmpty {
                    self.detail = "Apple Events are available for the open logbook. The peer service is \(self.rumlogPeerConnected ? "connected" : "waiting for RUMlog")."
                }
            }
        }
    }

    func chooseRumlogLogbook() {
        let panel = NSOpenPanel()
        panel.title = "Choose the RUMlog logbook"
        panel.prompt = "Choose Logbook"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url {
            settings.rumlogLogbookPath = url.path
            lastValidatedLogbookPath = nil
            lastLogbookValidationAt = nil
            Task { try? await fileStore?.saveSettings(settings) }
        }
    }

    func startBootstrap() {
        guard bootstrapTask == nil else { return }
        isBootstrapping = true
        bootstrapTask = Task {
            await perform("Preparing bootstrap…") {
                let wavelog = try self.makeWavelogClient()
                let rumlog = RumlogAppleEventClient(bundleIdentifier: self.settings.rumlogBundleIdentifier)
                try await self.validateOpenLogbook(force: true)
                let bootstrapStartedAt = Date()
                var state = try await self.fileStore?.loadBootstrapState(stationID: self.settings.stationID)
                    ?? BootstrapState(stationID: self.settings.stationID)
                var continuous = try await self.fileStore?.loadContinuousSyncState(stationID: self.settings.stationID)
                    ?? ContinuousSyncState(stationID: self.settings.stationID)

                guard let path = self.settings.rumlogLogbookPath, !path.isEmpty else {
                    throw WavelogClientError.invalidConfiguration("Choose the .rlog file currently open in RUMlogNG.")
                }
                let existingRecords = try await Task.detached {
                    try RumlogSQLiteReader(fileURL: URL(fileURLWithPath: path)).records()
                }.value
                for record in existingRecords {
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
            await perform("Synchronizing contacts and edits…") {
                let result = try await self.runContinuousSync()
                let edits = self.rumlogPeerConnected
                    ? try await self.runFullReconciliation()
                    : FullReconciliationResult()
                self.status = self.rumlogPeerConnected
                    ? "Sync complete"
                    : "Contacts synced; edit peer waiting"
                let peerNote = self.rumlogPeerConnected
                    ? ""
                    : " · edit reconciliation deferred until RUMlog peer reconnects"
                self.detail = "\(result.fromWavelog) new Wavelog rows checked · \(result.toWavelog) new contacts uploaded · \(edits.toRumlog) edits applied to RUMlog · \(edits.toWavelog) edits applied to Wavelog · \(edits.baselined) links baselined · \(edits.conflicts) conflicts · \(edits.deletionsHeld) deletions held\(peerNote)"
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
        guard let path = settings.rumlogLogbookPath, !path.isEmpty else {
            throw WavelogClientError.invalidConfiguration("Choose the .rlog file currently open in RUMlogNG.")
        }
        try await validateOpenLogbook()
        let wavelog = try makeWavelogClient()
        let rumlog = RumlogAppleEventClient(bundleIdentifier: settings.rumlogBundleIdentifier)
        var state = try await fileStore?.loadContinuousSyncState(stationID: settings.stationID)
            ?? ContinuousSyncState(stationID: settings.stationID)
        var received = 0
        var sent = 0
        let scanStarted = Date()
        let reader = RumlogSQLiteReader(fileURL: URL(fileURLWithPath: path))
        let needsInboundRecovery = state.pendingInboundFingerprints != nil
        let previousRowID = state.lastRumlogRowID
        let hasPriorBaseline = state.lastRumlogScanAt != nil && !state.knownFingerprints.isEmpty
        let recoveryRowCount = incrementalRecoveryRowCount
        let localRecords = try await Task.detached {
            if needsInboundRecovery {
                return try reader.records()
            }
            if let previousRowID {
                if let maximumRowID = try reader.maximumRowID(), previousRowID > maximumRowID {
                    return try reader.records()
                }
                return try reader.records(afterRowID: previousRowID)
            }
            if hasPriorBaseline, let maximumRowID = try reader.maximumRowID() {
                return try reader.records(afterRowID: max(0, maximumRowID - recoveryRowCount))
            }
            return try reader.records()
        }.value
        let highestLocalRowID = localRecords.compactMap(recordRumlogRowID).max()
        let recentLocalFingerprints = Set(localRecords.compactMap(\.semanticIdentityHash))
        var recoveryFingerprints: Set<String> = []
        if state.pendingInboundFingerprints != nil {
            recoveryFingerprints = Set(localRecords.compactMap(\.semanticIdentityHash))
        }
        if reconciliationState?.stationID != settings.stationID {
            reconciliationState = try await fileStore?.loadReconciliationState(stationID: settings.stationID)
        }
        let linkedRumlogRowIDs = Set(reconciliationState?.links.values.compactMap(\.rumlogRowID) ?? [])

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
                    !recordRumlogRowID(record).map(linkedRumlogRowIDs.contains).orFalse,
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
        if let highestLocalRowID {
            state.lastRumlogRowID = highestLocalRowID
        }
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
            var isFirstCycle = true
            while !Task.isCancelled {
                do {
                    let configuredDelay = TimeInterval(max(settings.pollIntervalSeconds, 15))
                    let delay = isFirstCycle
                        ? min(configuredDelay, automaticInitialDelaySeconds)
                        : configuredDelay
                    isFirstCycle = false
                    try await Task.sleep(for: .seconds(delay))
                } catch { break }
                guard !Task.isCancelled, !isBusy, bootstrap.completed,
                      settings.rumlogLogbookPath?.isEmpty == false else { continue }
                await perform("Automatic sync…") {
                    let result = try await self.runContinuousSync()
                    let now = Date()
                    let reconciliationReference = [
                        self.lastReconciliationAttemptAt,
                        self.lastReconciliationAt,
                    ].compactMap { $0 }.max()
                    let shouldReconcile = reconciliationReference.map {
                        now.timeIntervalSince($0) >= self.reconciliationIntervalSeconds
                    } ?? true
                    let canReconcile = self.rumlogPeerConnected
                        && now >= self.reconciliationNotBefore
                    var edits = FullReconciliationResult()
                    if shouldReconcile && canReconcile {
                        self.lastReconciliationAttemptAt = now
                        edits = try await self.runFullReconciliation()
                    }
                    self.status = self.rumlogPeerConnected
                        ? "Automatic sync complete"
                        : "Contacts synced; edit peer waiting"
                    let peerNote = self.rumlogPeerConnected
                        ? ""
                        : " · edit reconciliation deferred until RUMlog peer reconnects"
                    self.detail = "\(result.fromWavelog) new rows checked · \(result.toWavelog) new uploaded · \(edits.toRumlog + edits.toWavelog) edits synchronized\(peerNote)"
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

    private func validateOpenLogbook(force: Bool = false) async throws {
        guard let path = settings.rumlogLogbookPath, !path.isEmpty else {
            throw WavelogClientError.invalidConfiguration("Choose the .rlog file currently open in RUMlogNG.")
        }
        if !force,
           lastValidatedLogbookPath == path,
           let lastLogbookValidationAt,
           Date().timeIntervalSince(lastLogbookValidationAt) < logbookValidationCacheSeconds {
            return
        }

        let reader = RumlogSQLiteReader(fileURL: URL(fileURLWithPath: path))
        let latest = try await Task.detached { try reader.latestRecord() }.value
        let since: String
        if let latest, let snapshot = QSOEditableSnapshot(adif: latest) {
            let timestamp = "\(snapshot.qsoDate.prefix(4))-\(snapshot.qsoDate.dropFirst(4).prefix(2))-\(snapshot.qsoDate.suffix(2)) \(snapshot.timeOn.prefix(2)):\(snapshot.timeOn.dropFirst(2).prefix(2)):\(snapshot.timeOn.suffix(2))"
            guard let date = Self.sqlDateFormatter.date(from: timestamp) else {
                throw RumlogAppleEventError.logbookMismatch(path)
            }
            since = Self.sqlDateFormatter.string(from: date.addingTimeInterval(-600))
        } else {
            since = "1970-01-01 00:00:00"
        }

        let rumlog = RumlogAppleEventClient(bundleIdentifier: settings.rumlogBundleIdentifier)
        let exported = try await Task.detached {
            try rumlog.exportADIF(since: since)
        }.value
        let exportedRecords = ADIFParser().records(in: exported)
        if let latest, let fingerprint = latest.semanticIdentityHash {
            guard exportedRecords.contains(where: { $0.semanticIdentityHash == fingerprint }) else {
                throw RumlogAppleEventError.logbookMismatch(path)
            }
        } else if !exportedRecords.isEmpty {
            throw RumlogAppleEventError.logbookMismatch(path)
        }
        lastValidatedLogbookPath = path
        lastLogbookValidationAt = Date()
    }

    private func refreshRumlogState() {
        let rumlog = RumlogAppleEventClient(bundleIdentifier: settings.rumlogBundleIdentifier)
        rumlogInstalled = rumlog.isInstalled()
        rumlogInstanceCount = rumlog.runningInstanceCount()
        rumlogRunning = rumlogInstanceCount > 0
    }

    private func startPeerBridge() {
        peerBridge?.stop()
        do {
            let peer = RumlogPeerBridge(
                port: settings.rumlogUDPPort,
                logName: "\(settings.stationName) via Wavelog"
            ) { [weak self] connected, message in
                Task { @MainActor [weak self] in
                    self?.refreshRumlogState()
                    self?.rumlogPeerConnected = connected
                    self?.rumlogPeerStatus = message
                }
            }
            try peer.start()
            peerBridge = peer
        } catch {
            peerBridge = nil
            rumlogPeerConnected = false
            rumlogPeerStatus = error.localizedDescription
        }
    }

    private func runFullReconciliation() async throws -> FullReconciliationResult {
        guard bootstrap.completed else {
            throw WavelogClientError.invalidConfiguration("Complete the initial bootstrap before reconciling edits.")
        }
        guard let peerBridge else {
            throw RumlogPeerBridgeError.socketFailure(rumlogPeerStatus)
        }
        guard peerBridge.isConnected else { throw RumlogPeerBridgeError.notConnected }
        guard let path = settings.rumlogLogbookPath, !path.isEmpty else {
            throw WavelogClientError.invalidConfiguration("Choose the .rlog file currently open in RUMlogNG.")
        }
        try await validateOpenLogbook()
        let wavelog = try makeWavelogClient()
        let rumlog = RumlogAppleEventClient(bundleIdentifier: settings.rumlogBundleIdentifier)
        status = "Reading the complete RUMlog logbook…"
        let localRecords = try await Task.detached {
            try RumlogSQLiteReader(fileURL: URL(fileURLWithPath: path)).records()
        }.value
        var remoteQSOs: [WavelogQSO] = []
        var pageNumber = 1
        while true {
            status = "Reading Wavelog contacts for edit reconciliation…"
            detail = "Page \(pageNumber) · \(remoteQSOs.count.formatted()) contacts loaded"
            let page = try await wavelog.listQSOs(page: pageNumber, perPage: 5_000)
            remoteQSOs.append(contentsOf: page.data)
            if !page.meta.hasMore { break }
            pageNumber += 1
        }
        let uniqueRemoteQSOs = deduplicatedWavelogQSOs(remoteQSOs)
        status = "Indexing contacts for edit reconciliation…"
        if uniqueRemoteQSOs.count != remoteQSOs.count {
            detail = "\((remoteQSOs.count - uniqueRemoteQSOs.count).formatted()) repeated page row(s) safely ignored"
        }
        let index = await Task.detached {
            ReconciliationIndex(localRecords: localRecords, remoteQSOs: uniqueRemoteQSOs)
        }.value
        let localEntries = index.localEntries
        let localGroups = index.localGroups
        let remoteByID = index.remoteByID
        let remoteGroups = index.remoteGroups
        var state: ReconciliationState
        if let cached = reconciliationState, cached.stationID == settings.stationID {
            state = cached
        } else {
            state = try await fileStore?.loadReconciliationState(stationID: settings.stationID)
                ?? ReconciliationState(stationID: settings.stationID)
        }
        var result = FullReconciliationResult()

        if state.links.isEmpty {
            state.links = await Task.detached {
                var links: [Int: ReconciliationLink] = [:]
                for (hash, localGroup) in localGroups where localGroup.count == 1 {
                    guard let remoteGroup = remoteGroups[hash], remoteGroup.count == 1 else { continue }
                    let local = localGroup[0]
                    let remote = remoteGroup[0]
                    links[remote.qso.id] = ReconciliationLink(
                        wavelogID: remote.qso.id,
                        rumlogRowID: recordRumlogRowID(local.record),
                        local: local.snapshot,
                        remote: remote.snapshot
                    )
                }
                return links
            }.value
            let completedAt = Date()
            state.lastRunAt = completedAt
            try await fileStore?.saveReconciliationState(state)
            reconciliationState = state
            lastReconciliationAt = completedAt
            var continuous = try await fileStore?.loadContinuousSyncState(stationID: settings.stationID)
                ?? ContinuousSyncState(stationID: settings.stationID)
            continuous.knownFingerprints.formUnion(state.links.values.map(\.semanticIdentityHash))
            continuous.lastReconciliationAt = completedAt
            try await fileStore?.saveContinuousSyncState(continuous)
            syncState = continuous
            result.baselined = state.links.count
            return result
        }

        if settings.rumlogLogbookPath?.isEmpty == false,
           state.localSnapshotVersion != RumlogSQLiteReader.snapshotVersion {
            var migrated = 0
            var held = 0
            for remoteID in state.links.keys.sorted() {
                guard
                    var link = state.links[remoteID],
                    let remote = remoteByID[remoteID],
                    let localGroup = localGroups[link.semanticIdentityHash],
                    localGroup.count == 1,
                    let local = localGroup.first
                else {
                    held += 1
                    continue
                }
                let localBaseline = link.rumlogSnapshot.baseliningNewlySupportedFields(
                    from: local.snapshot
                )
                let remoteBaseline = link.wavelogSnapshot.baseliningNewlySupportedFields(
                    from: remote.snapshot
                )
                link.rumlogRowID = recordRumlogRowID(local.record)
                link.rumlogSnapshot = localBaseline
                link.wavelogSnapshot = remoteBaseline
                link.rumlogContentHash = localBaseline.contentHash
                link.wavelogContentHash = remoteBaseline.contentHash
                state.links[remoteID] = link
                migrated += 1
            }
            state.localSnapshotVersion = RumlogSQLiteReader.snapshotVersion
            let completedAt = Date()
            state.lastRunAt = completedAt
            result.baselined += migrated
            result.conflicts += held
            try await fileStore?.saveReconciliationState(state)
            reconciliationState = state
            lastReconciliationAt = completedAt
            var continuous = try await fileStore?.loadContinuousSyncState(stationID: settings.stationID)
                ?? ContinuousSyncState(stationID: settings.stationID)
            continuous.knownFingerprints.formUnion(state.links.values.map(\.semanticIdentityHash))
            continuous.lastReconciliationAt = completedAt
            try await fileStore?.saveContinuousSyncState(continuous)
            syncState = continuous
            return result
        }

        var linkedSemanticHashes = Set(state.links.values.map(\.semanticIdentityHash))
        var stateDirty = false
        for remoteID in state.links.keys.sorted() {
            guard var link = state.links[remoteID], let remote = remoteByID[remoteID] else {
                result.deletionsHeld += 1
                continue
            }
            var local = localGroups[link.semanticIdentityHash]?.count == 1
                ? localGroups[link.semanticIdentityHash]?[0]
                : nil

            if local == nil, remote.snapshot.contentHash == link.wavelogContentHash {
                let candidates = localEntries.filter {
                    !linkedSemanticHashes.contains($0.snapshot.semanticIdentityHash) &&
                        $0.snapshot.nonIdentityContentHash == link.rumlogSnapshot.nonIdentityContentHash &&
                        $0.snapshot.identityDifferenceCount(from: link.rumlogSnapshot) == 1
                }
                if candidates.count == 1 { local = candidates[0] }
            }
            guard let local else {
                result.deletionsHeld += 1
                continue
            }
            link.rumlogRowID = recordRumlogRowID(local.record)

            switch reconciliationDecision(link: link, local: local.snapshot, remote: remote.snapshot) {
            case .alignBaselines:
                linkedSemanticHashes.remove(link.semanticIdentityHash)
                link.semanticIdentityHash = local.snapshot.semanticIdentityHash
                linkedSemanticHashes.insert(link.semanticIdentityHash)
                link.rumlogSnapshot = local.snapshot
                link.wavelogSnapshot = remote.snapshot
                link.rumlogContentHash = local.snapshot.contentHash
                link.wavelogContentHash = remote.snapshot.contentHash
                updateReconciliationLink(link, id: remoteID, state: &state, dirty: &stateDirty)
                continue
            case .conflict:
                updateReconciliationLink(link, id: remoteID, state: &state, dirty: &stateDirty)
                result.conflicts += 1
                continue
            case .updateWavelog:
                guard local.snapshot.semanticIdentityHash == link.semanticIdentityHash ||
                        !linkedSemanticHashes.contains(local.snapshot.semanticIdentityHash) else {
                    result.conflicts += 1
                    continue
                }
                let update = local.snapshot.wavelogUpdate(changesFrom: link.rumlogSnapshot)
                _ = try await wavelog.updateQSO(id: remoteID, fields: update)
                let readback = try await wavelog.getQSO(id: remoteID)
                guard let readbackSnapshot = QSOEditableSnapshot(wavelog: readback) else {
                    throw WavelogClientError.invalidResponse
                }
                let expected = remote.snapshot.mergingChanges(
                    from: link.rumlogSnapshot,
                    to: local.snapshot
                )
                guard readbackSnapshot == expected else {
                    throw WavelogClientError.writeVerificationFailed(id: remoteID)
                }
                linkedSemanticHashes.remove(link.semanticIdentityHash)
                link.semanticIdentityHash = local.snapshot.semanticIdentityHash
                linkedSemanticHashes.insert(link.semanticIdentityHash)
                link.rumlogSnapshot = local.snapshot
                link.wavelogSnapshot = readbackSnapshot
                link.rumlogContentHash = local.snapshot.contentHash
                link.wavelogContentHash = readbackSnapshot.contentHash
                updateReconciliationLink(link, id: remoteID, state: &state, dirty: &stateDirty)
                result.toWavelog += 1
            case .updateRumlog:
                let targetSnapshot = local.snapshot.mergingChanges(
                    from: link.wavelogSnapshot,
                    to: remote.snapshot
                )
                guard targetSnapshot.semanticIdentityHash == link.semanticIdentityHash ||
                        !linkedSemanticHashes.contains(targetSnapshot.semanticIdentityHash) else {
                    result.conflicts += 1
                    continue
                }
                let replacement = targetSnapshot.applying(to: local.record)
                try peerBridge.sendReplacement(old: local.record, new: replacement)
                let verified = try await verifyRumlogReplacement(
                    expected: targetSnapshot,
                    originalRowID: recordRumlogRowID(local.record),
                    expectedCount: localRecords.count,
                    rumlog: rumlog
                )
                linkedSemanticHashes.remove(link.semanticIdentityHash)
                link.semanticIdentityHash = targetSnapshot.semanticIdentityHash
                linkedSemanticHashes.insert(link.semanticIdentityHash)
                link.rumlogRowID = recordRumlogRowID(verified)
                link.rumlogSnapshot = targetSnapshot
                link.wavelogSnapshot = remote.snapshot
                link.rumlogContentHash = targetSnapshot.contentHash
                link.wavelogContentHash = remote.snapshot.contentHash
                updateReconciliationLink(link, id: remoteID, state: &state, dirty: &stateDirty)
                result.toRumlog += 1
            case .unchanged:
                updateReconciliationLink(link, id: remoteID, state: &state, dirty: &stateDirty)
                continue
            }
        }

        for (hash, localGroup) in localGroups where localGroup.count == 1 {
            guard
                let remoteGroup = remoteGroups[hash], remoteGroup.count == 1,
                state.links[remoteGroup[0].qso.id] == nil
            else { continue }
            state.links[remoteGroup[0].qso.id] = ReconciliationLink(
                wavelogID: remoteGroup[0].qso.id,
                rumlogRowID: recordRumlogRowID(localGroup[0].record),
                local: localGroup[0].snapshot,
                remote: remoteGroup[0].snapshot
            )
            stateDirty = true
            result.baselined += 1
        }
        let completedAt = Date()
        if stateDirty {
            state.lastRunAt = completedAt
            try await fileStore?.saveReconciliationState(state)
        }
        reconciliationState = state
        lastReconciliationAt = completedAt
        var continuous = try await fileStore?.loadContinuousSyncState(stationID: settings.stationID)
            ?? ContinuousSyncState(stationID: settings.stationID)
        continuous.knownFingerprints.formUnion(state.links.values.map(\.semanticIdentityHash))
        continuous.lastReconciliationAt = completedAt
        try await fileStore?.saveContinuousSyncState(continuous)
        syncState = continuous
        return result
    }

    private func verifyRumlogReplacement(
        expected: QSOEditableSnapshot,
        originalRowID: Int64?,
        expectedCount: Int,
        rumlog: RumlogAppleEventClient
    ) async throws -> ADIFRecord {
        if let path = settings.rumlogLogbookPath, !path.isEmpty, let originalRowID {
            let reader = RumlogSQLiteReader(fileURL: URL(fileURLWithPath: path))
            for attempt in 0..<20 {
                if attempt > 0 { try await Task.sleep(for: .milliseconds(250)) }
                let count = try reader.count()
                if count == expectedCount {
                    if let record = try reader.record(id: originalRowID),
                       QSOEditableSnapshot(adif: record) == expected {
                        return record
                    }
                    let replacements = try reader.records(matching: expected).filter {
                        QSOEditableSnapshot(adif: $0) == expected
                    }
                    if replacements.count == 1, let replacement = replacements.first {
                        return replacement
                    }
                }
            }
            throw RumlogPeerBridgeError.writeVerificationFailed
        }

        try await Task.sleep(for: .milliseconds(750))
        let adif = try await Task.detached {
            try rumlog.exportADIF(since: "1970-01-01 00:00:00")
        }.value
        let matches = ADIFParser().records(in: adif).filter {
            QSOEditableSnapshot(adif: $0) == expected
        }
        guard matches.count == 1, let match = matches.first else {
            throw RumlogPeerBridgeError.writeVerificationFailed
        }
        return match
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

private struct LocalReconciliationEntry: Sendable {
    let record: ADIFRecord
    let snapshot: QSOEditableSnapshot
    let semanticIdentityHash: String
    let contentHash: String

    init(record: ADIFRecord, snapshot: QSOEditableSnapshot) {
        self.record = record
        self.snapshot = snapshot
        semanticIdentityHash = snapshot.semanticIdentityHash
        contentHash = snapshot.contentHash
    }
}

private struct RemoteReconciliationEntry: Sendable {
    let qso: WavelogQSO
    let snapshot: QSOEditableSnapshot
    let semanticIdentityHash: String
    let contentHash: String

    init(qso: WavelogQSO, snapshot: QSOEditableSnapshot) {
        self.qso = qso
        self.snapshot = snapshot
        semanticIdentityHash = snapshot.semanticIdentityHash
        contentHash = snapshot.contentHash
    }
}

private struct ReconciliationIndex: Sendable {
    let localEntries: [LocalReconciliationEntry]
    let localGroups: [String: [LocalReconciliationEntry]]
    let remoteByID: [Int: RemoteReconciliationEntry]
    let remoteGroups: [String: [RemoteReconciliationEntry]]

    init(localRecords: [ADIFRecord], remoteQSOs: [WavelogQSO]) {
        let localEntries = localRecords.compactMap { record -> LocalReconciliationEntry? in
            guard let snapshot = QSOEditableSnapshot(adif: record) else { return nil }
            return LocalReconciliationEntry(record: record, snapshot: snapshot)
        }
        let remoteEntries = remoteQSOs.compactMap { qso -> RemoteReconciliationEntry? in
            guard let snapshot = QSOEditableSnapshot(wavelog: qso) else { return nil }
            return RemoteReconciliationEntry(qso: qso, snapshot: snapshot)
        }
        self.localEntries = localEntries
        localGroups = Dictionary(grouping: localEntries, by: \.semanticIdentityHash)
        var uniqueRemoteEntries: [Int: RemoteReconciliationEntry] = [:]
        uniqueRemoteEntries.reserveCapacity(remoteEntries.count)
        for entry in remoteEntries {
            uniqueRemoteEntries[entry.qso.id] = entry
        }
        remoteByID = uniqueRemoteEntries
        remoteGroups = Dictionary(grouping: Array(uniqueRemoteEntries.values), by: \.semanticIdentityHash)
    }
}

private func recordRumlogRowID(_ record: ADIFRecord) -> Int64? {
    record["APP_RUMLOG_ROWID"].flatMap(Int64.init)
}

private func updateReconciliationLink(
    _ link: ReconciliationLink,
    id: Int,
    state: inout ReconciliationState,
    dirty: inout Bool
) {
    if state.links[id] != link {
        state.links[id] = link
        dirty = true
    }
}

private extension Optional where Wrapped == Bool {
    var orFalse: Bool { self ?? false }
}

private struct FullReconciliationResult {
    var toRumlog = 0
    var toWavelog = 0
    var conflicts = 0
    var deletionsHeld = 0
    var baselined = 0
}
