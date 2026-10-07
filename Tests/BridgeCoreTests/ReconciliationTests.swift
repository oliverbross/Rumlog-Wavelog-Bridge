import Foundation
import Testing
@testable import BridgeCore

@Test func editableSnapshotsNormalizeProviderRepresentations() throws {
    let localRecord = ADIFRecord(fields: [
        "CALL": "hb9oau/p",
        "QSO_DATE": "20261004",
        "TIME_ON": "074732",
        "BAND": "40M",
        "MODE": "SSB",
        "FREQ": "7.102000",
        "RST_SENT": "59",
        "RST_RCVD": "59",
        "COMMENT": "test note",
    ])
    let json = Data("""
    {"id":178162,"station_id":1,"call":"HB9OAU/P","band":"40m","mode":"SSB","submode":null,"freq":"7102000","freq_rx":null,"qso_date":"2026-10-04 07:47:32","rst_sent":"59","rst_rcvd":"59","gridsquare":null,"name":"","comment":"test note","notes":"","qth":""}
    """.utf8)
    let remoteQSO = try JSONDecoder().decode(WavelogQSO.self, from: json)
    let local = try #require(QSOEditableSnapshot(adif: localRecord))
    let remote = try #require(QSOEditableSnapshot(wavelog: remoteQSO))

    #expect(local.semanticIdentityHash == remote.semanticIdentityHash)
    #expect(local.contentHash == remote.contentHash)
}

@Test func reconciliationBuildsOnlyTheChangedWavelogFields() throws {
    let original = try #require(QSOEditableSnapshot(adif: ADIFRecord(fields: [
        "CALL": "HB9OAU/P", "QSO_DATE": "20261004", "TIME_ON": "074732",
        "BAND": "40m", "MODE": "SSB", "FREQ": "7.102000", "COMMENT": "",
    ])))
    var edited = original
    edited.note = "EDITED IN RUMLOG"
    let update = edited.wavelogUpdate(changesFrom: original)
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any]

    #expect(encoded?["comment"] as? String == "EDITED IN RUMLOG")
    #expect(encoded?["call"] == nil)
    #expect(encoded?["qso_date"] == nil)
}

@Test func reconciliationAlignsEquivalentCurrentRecordsWithoutProviderWrites() throws {
    var oldLocal = try #require(QSOEditableSnapshot(adif: ADIFRecord(fields: [
        "CALL": "DJ2DX", "QSO_DATE": "20221012", "TIME_ON": "162701",
        "BAND": "40m", "MODE": "SSB", "FREQ": "7.101200", "STATE": "",
    ])))
    var remote = oldLocal
    remote.state = "BW"
    let link = ReconciliationLink(wavelogID: 110841, local: oldLocal, remote: remote)
    oldLocal.state = "BW"

    #expect(reconciliationDecision(link: link, local: oldLocal, remote: remote) == .alignBaselines)
}

@Test func reconciliationAlignsSameEditAcrossDivergentProviderDefaults() throws {
    var localBaseline = try #require(QSOEditableSnapshot(adif: ADIFRecord(fields: [
        "CALL": "HB9OAU/P", "QSO_DATE": "20261004", "TIME_ON": "074732",
        "BAND": "40m", "MODE": "SSB", "FREQ": "7.102000", "COMMENT": "OLD",
        "TX_PWR": "500",
    ])))
    var remoteBaseline = localBaseline
    remoteBaseline.power = ""
    let link = ReconciliationLink(wavelogID: 178162, local: localBaseline, remote: remoteBaseline)
    localBaseline.note = "SAME EDIT"
    remoteBaseline.note = "SAME EDIT"

    #expect(localBaseline.contentHash != remoteBaseline.contentHash)
    #expect(reconciliationDecision(link: link, local: localBaseline, remote: remoteBaseline) == .alignBaselines)
}

@Test func reconciliationDistinguishesOneSidedAndConcurrentEdits() throws {
    let original = try #require(QSOEditableSnapshot(adif: ADIFRecord(fields: [
        "CALL": "HB9OAU/P", "QSO_DATE": "20261004", "TIME_ON": "074732",
        "BAND": "40m", "MODE": "SSB", "FREQ": "7.102000", "COMMENT": "",
    ])))
    let link = ReconciliationLink(wavelogID: 178162, local: original, remote: original)
    var local = original
    local.note = "LOCAL"
    var remote = original
    remote.note = "REMOTE"

    #expect(reconciliationDecision(link: link, local: local, remote: original) == .updateWavelog)
    #expect(reconciliationDecision(link: link, local: original, remote: remote) == .updateRumlog)
    #expect(reconciliationDecision(link: link, local: local, remote: remote) == .conflict)
}

@Test func reconciliationHoldsFieldsThatRumlogCannotPersist() throws {
    let local = try #require(QSOEditableSnapshot(adif: ADIFRecord(fields: [
        "CALL": "HB9OAU/P", "QSO_DATE": "20261004", "TIME_ON": "074732",
        "BAND": "40m", "MODE": "SSB", "FREQ": "7.102000",
    ])))
    var remote = local
    remote.propagationMode = "SAT"
    remote.sotaReference = "HB/BE-001"
    remote.potaReference = "US-0001"
    remote.wwffReference = "VKFF-0001"
    let link = ReconciliationLink(wavelogID: 178162, local: local, remote: remote)

    #expect(local != remote)
    #expect(local.contentHash == remote.contentHash)
    #expect(reconciliationDecision(link: link, local: local, remote: remote) == .unchanged)

    var changedRemote = remote
    changedRemote.wwffReference = "VKFF-0002"
    #expect(reconciliationDecision(link: link, local: local, remote: changedRemote) == .unchanged)
}

@Test func oldReconciliationStateDecodesAsNeedingLocalSnapshotMigration() throws {
    let state = try JSONDecoder().decode(
        ReconciliationState.self,
        from: Data(#"{"stationID":1,"links":{},"lastRunAt":null}"#.utf8)
    )
    #expect(state.localSnapshotVersion == nil)
    #expect(ReconciliationState(stationID: 1).localSnapshotVersion == RumlogSQLiteReader.snapshotVersion)
}

@Test func legacyContinuousSyncStateDecodesWithoutIncrementalCheckpoints() throws {
    let state = try JSONDecoder().decode(
        ContinuousSyncState.self,
        from: Data(#"{"stationID":1,"lastWavelogID":42,"lastRumlogScanAt":null,"knownFingerprints":[],"lastSuccessAt":null}"#.utf8)
    )

    #expect(state.lastRumlogRowID == nil)
    #expect(state.lastReconciliationAt == nil)
}

@Test func duplicateWavelogPageRowsAreDeduplicatedByID() throws {
    let data = Data(#"""
    [
      {"id":178162,"station_id":1,"call":"HB9OAU/P","band":"40m","mode":"SSB","freq":"7102000","qso_date":"2026-10-04 07:47:32","comment":"first"},
      {"id":178162,"station_id":1,"call":"HB9OAU/P","band":"40m","mode":"SSB","freq":"7102000","qso_date":"2026-10-04 07:47:32","comment":"latest"}
    ]
    """#.utf8)
    let rows = try JSONDecoder().decode([WavelogQSO].self, from: data)
    let deduplicated = deduplicatedWavelogQSOs(rows)

    #expect(deduplicated.count == 1)
    #expect(deduplicated.first?.id == 178162)
    #expect(deduplicated.first?.comment == "latest")
}

@Test func legacyEditableSnapshotDecodesWithNewFieldsEmpty() throws {
    let data = Data(#"""
    {
        "call":"HB9OAU/P","qsoDate":"20261004","timeOn":"074732",
        "band":"40m","mode":"SSB","frequencyHz":"7102000",
        "rstSent":"59","rstReceived":"59","gridSquare":"","name":"",
        "note":"","qth":"","state":"","county":"","iota":"",
        "qslVia":"","propagationMode":"","satelliteName":"",
        "satelliteMode":"","sotaReference":"","potaReference":"",
        "wwffReference":""
    }
    """#.utf8)
    let snapshot = try JSONDecoder().decode(QSOEditableSnapshot.self, from: data)

    #expect(snapshot.receiveBand == "")
    #expect(snapshot.power == "")
    #expect(snapshot.cqZone == "")
    #expect(snapshot.ituZone == "")
}

@Test func snapshotMigrationBaselinesOnlyNewlySupportedFields() throws {
    var old = try #require(QSOEditableSnapshot(adif: ADIFRecord(fields: [
        "CALL": "HB9OAU/P", "QSO_DATE": "20261004", "TIME_ON": "074732",
        "BAND": "40m", "MODE": "SSB", "FREQ": "7.102000", "COMMENT": "OLD",
    ])))
    var current = old
    current.note = "PENDING EDIT"
    current.receiveBand = "40m"
    current.power = "500"
    current.cqZone = "14"
    current.ituZone = "28"

    old = old.baseliningNewlySupportedFields(from: current)

    #expect(old.note == "OLD")
    #expect(old.receiveBand == "40m")
    #expect(old.power == "500")
    #expect(old.cqZone == "14")
    #expect(old.ituZone == "28")
    #expect(old.contentHash != current.contentHash)
}

@Test func rumlogPeerArchiveUsesTheObservedQsoClass() throws {
    let record = ADIFRecord(fields: [
        "CALL": "9H1CJ", "QSO_DATE": "20221008", "TIME_ON": "150236",
        "BAND": "15m", "MODE": "SSB", "FREQ": "21.317800",
        "RST_SENT": "55", "RST_RCVD": "57", "COMMENT": "PEER TEST",
        "DXCC": "257", "PFX": "9H1", "APP_RUMLOG_DXCC": "9H",
    ])
    let maybeArchive = try RumlogQSOArchive.make(record: record, deletionIdentityOnly: false)
    let archive = try #require(maybeArchive)

    #expect(archive.starts(with: Data("bplist00".utf8)))
    #expect(archive.range(of: Data("QsoClass".utf8)) != nil)
    #expect(archive.range(of: Data("PEER TEST".utf8)) != nil)

    let propertyList = try #require(
        PropertyListSerialization.propertyList(from: archive, format: nil) as? [String: Any]
    )
    let objects = try #require(propertyList["$objects"] as? [Any])
    let root = try #require(objects[1] as? [String: Any])
    #expect(root["adif"] as? Int == 257)
    #expect(root["checked"] as? Bool == false)
    #expect(root["opIsValid"] as? Bool == true)
    #expect(root["qrg"] as? Double == 21_317.8)
    #expect(root["rowid"] as? Int == 1)

    let wire = RumlogPeerWire.message(kind: "QsoLogged", archive: archive, stationName: "Bridge Test")
    let wireText = try #require(String(data: wire, encoding: .utf8))
    #expect(wireText.contains("<RUMlogNG>"))
    #expect(wireText.contains("<StationName>Bridge Test</StationName>"))
    #expect(wireText.contains("<QsoLogged>"))
    #expect(wireText.hasSuffix("B0UnDary_73"))

    if let directory = ProcessInfo.processInfo.environment["RUMLOG_ARCHIVE_OUTPUT_DIR"] {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try archive.write(to: output.appendingPathComponent("generated-logged.bplist"), options: .atomic)
        let maybeDeletion = try RumlogQSOArchive.make(record: record, deletionIdentityOnly: true)
        let deletion = try #require(maybeDeletion)
        try deletion.write(to: output.appendingPathComponent("generated-deleted.bplist"), options: .atomic)
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_RUMLOG_SQLITE_READ"] == "1"))
func readsTheLiveRumlogLogbookWithoutWriting() throws {
    let path = try #require(ProcessInfo.processInfo.environment["RUMLOG_LOGBOOK_PATH"])
    let reader = RumlogSQLiteReader(fileURL: URL(fileURLWithPath: path))
    let records = try reader.records()
    #expect(!records.isEmpty)
    #expect(try reader.count() == records.count)
    #expect(records.allSatisfy { Int64($0["APP_RUMLOG_ROWID"] ?? "") != nil })
    let maybeMaximumRowID = try reader.maximumRowID()
    let maximumRowID = try #require(maybeMaximumRowID)
    let recent = try reader.records(afterRowID: max(0, maximumRowID - 10))
    #expect(recent.allSatisfy { (Int64($0["APP_RUMLOG_ROWID"] ?? "") ?? 0) > maximumRowID - 10 })
    #expect(recent.last?["APP_RUMLOG_ROWID"] == String(maximumRowID))
    #expect(try reader.records(afterRowID: maximumRowID).isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_RUMLOG_PEER_LAB"] == "1"))
func replacesAndRestoresAContactThroughTheProductionPeerBridge() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["RUMLOG_LAB_LOGBOOK_PATH"])
    let port = try #require(UInt16(ProcessInfo.processInfo.environment["RUMLOG_LAB_PORT"] ?? ""))
    let reader = RumlogSQLiteReader(fileURL: URL(fileURLWithPath: path))
    let maybeBefore = try reader.record(id: 1)
    let before = try #require(maybeBefore)
    let beforeSnapshot = try #require(QSOEditableSnapshot(adif: before))
    let beforeCount = try reader.count()
    let bridge = RumlogPeerBridge(
        port: port,
        stationName: "Wavelog Bridge Archive Lab",
        logName: "generated-archive-lab.rlog"
    )
    try bridge.start()
    defer { bridge.stop() }

    for _ in 0..<40 where !bridge.isConnected {
        try await Task.sleep(for: .milliseconds(250))
    }
    #expect(bridge.isConnected)

    var editedSnapshot = beforeSnapshot
    editedSnapshot.note = "PRODUCTION-BRIDGE-LAB-ROUNDTRIP"
    let edited = editedSnapshot.applying(to: before)
    try bridge.sendReplacement(old: before, new: edited)
    var observedEdited: ADIFRecord?
    for _ in 0..<40 {
        try await Task.sleep(for: .milliseconds(250))
        if let candidate = try reader.record(id: 1),
           QSOEditableSnapshot(adif: candidate) == editedSnapshot {
            observedEdited = candidate
            break
        }
    }
    let applied = try #require(observedEdited)
    #expect(try reader.count() == beforeCount)
    #expect(try reader.records(matching: editedSnapshot).count == 1)

    try bridge.sendReplacement(old: applied, new: beforeSnapshot.applying(to: applied))
    var restored = false
    for _ in 0..<40 {
        try await Task.sleep(for: .milliseconds(250))
        if let candidate = try reader.record(id: 1),
           QSOEditableSnapshot(adif: candidate) == beforeSnapshot {
            restored = true
            break
        }
    }
    #expect(restored)
    #expect(try reader.count() == beforeCount)
    #expect(try reader.records(matching: beforeSnapshot).count == 1)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_RUMLOG_PEER_LIVE_EDIT"] == "1"))
func appliesAnAuthorizedLiveRumlogEditThroughThePeerBridge() async throws {
    let environment = ProcessInfo.processInfo.environment
    let path = try #require(environment["RUMLOG_LOGBOOK_PATH"])
    let rowID = try #require(Int64(environment["RUMLOG_ROW_ID"] ?? ""))
    let note = try #require(environment["RUMLOG_EDIT_NOTE"])
    let port = try #require(UInt16(environment["RUMLOG_PEER_PORT"] ?? "12060"))
    let reader = RumlogSQLiteReader(fileURL: URL(fileURLWithPath: path))
    let maybeBefore = try reader.record(id: rowID)
    let before = try #require(maybeBefore)
    let beforeCount = try reader.count()
    var expected = try #require(QSOEditableSnapshot(adif: before))
    expected.note = note
    let bridge = RumlogPeerBridge(
        port: port,
        stationName: "Wavelog Bridge",
        logName: ProcessInfo.processInfo.environment["RUMLOG_PEER_LOG_NAME"] ?? "Wavelog via RUMlog"
    )
    try bridge.start()
    defer { bridge.stop() }

    for _ in 0..<240 where !bridge.isConnected {
        try await Task.sleep(for: .milliseconds(250))
    }
    #expect(bridge.isConnected)
    try bridge.sendReplacement(old: before, new: expected.applying(to: before))
    var matches: [ADIFRecord] = []
    for _ in 0..<60 {
        try await Task.sleep(for: .milliseconds(250))
        matches = try reader.records(matching: expected).filter {
            QSOEditableSnapshot(adif: $0) == expected
        }
        if try reader.count() == beforeCount, matches.count == 1 { break }
    }
    #expect(try reader.count() == beforeCount)
    #expect(matches.count == 1)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_RECONCILIATION_DIAGNOSTIC"] == "1"))
func diagnosesLiveReconciliationRepresentationChanges() throws {
    let logbookPath = try #require(ProcessInfo.processInfo.environment["RUMLOG_LOGBOOK_PATH"])
    let statePath = try #require(ProcessInfo.processInfo.environment["RECONCILIATION_STATE_PATH"])
    let records = try RumlogSQLiteReader(fileURL: URL(fileURLWithPath: logbookPath)).records()
    let stateData = try Data(contentsOf: URL(fileURLWithPath: statePath))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let state = try decoder.decode(ReconciliationState.self, from: stateData)
    let snapshots = records.compactMap(QSOEditableSnapshot.init(adif:))
    let byIdentity = Dictionary(grouping: snapshots, by: \.semanticIdentityHash)
    let inconsistent = state.links.values.filter {
        $0.rumlogSnapshot.contentHash != $0.rumlogContentHash ||
            $0.wavelogSnapshot.contentHash != $0.wavelogContentHash
    }
    let changed = state.links.values.sorted { $0.wavelogID < $1.wavelogID }.compactMap { link -> ReconciliationLink? in
        guard let group = byIdentity[link.semanticIdentityHash], group.count == 1 else { return nil }
        return group[0].contentHash == link.rumlogContentHash ? nil : link
    }

    print("DIAGNOSTIC_INCONSISTENT_BASELINES=\(inconsistent.count)")
    print("DIAGNOSTIC_CHANGED_COUNT=\(changed.count)")
    for link in changed.prefix(25) {
        guard let current = byIdentity[link.semanticIdentityHash]?.first else { continue }
        print("DIAGNOSTIC_WAVELOG_ID=\(link.wavelogID)")
        print("BASELINE=\(link.rumlogSnapshot)")
        print("CURRENT=\(current)")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_WAVELOG_RECONCILIATION_DIAGNOSTIC"] == "1"))
func diagnosesLiveWavelogChangesAgainstTheSavedBaseline() async throws {
    let token = try #require(ProcessInfo.processInfo.environment["WAVELOG_TOKEN"])
    let baseURL = try #require(URL(string: ProcessInfo.processInfo.environment["WAVELOG_URL"] ?? ""))
    let statePath = try #require(ProcessInfo.processInfo.environment["RECONCILIATION_STATE_PATH"])
    let stateData = try Data(contentsOf: URL(fileURLWithPath: statePath))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let state = try decoder.decode(ReconciliationState.self, from: stateData)
    let stationID = try #require(Int(ProcessInfo.processInfo.environment["WAVELOG_STATION_ID"] ?? ""))
    let client = WavelogClient(configuration: try WavelogConfiguration(
        baseURL: baseURL,
        token: token,
        stationID: stationID
    ))
    var remote: [Int: QSOEditableSnapshot] = [:]
    var pageNumber = 1
    while true {
        let page = try await client.listQSOs(page: pageNumber, perPage: 5_000)
        for qso in page.data {
            if let snapshot = QSOEditableSnapshot(wavelog: qso) { remote[qso.id] = snapshot }
        }
        if !page.meta.hasMore { break }
        pageNumber += 1
    }
    let changed = state.links.values.sorted { $0.wavelogID < $1.wavelogID }.filter { link in
        remote[link.wavelogID]?.contentHash != link.wavelogContentHash
    }
    print("WAVELOG_DIAGNOSTIC_CHANGED_COUNT=\(changed.count)")
    for link in changed {
        guard let current = remote[link.wavelogID] else { continue }
        let restore = link.wavelogSnapshot.wavelogUpdate(changesFrom: current)
        let json = String(decoding: try JSONEncoder().encode(restore), as: UTF8.self)
        print("WAVELOG_DIAGNOSTIC_ID=\(link.wavelogID) RESTORE=\(json)")
    }
}
