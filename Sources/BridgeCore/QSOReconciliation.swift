import CryptoKit
import Foundation

public struct QSOEditableSnapshot: Codable, Equatable, Sendable {
    public var call: String
    public var qsoDate: String
    public var timeOn: String
    public var band: String
    public var mode: String
    public var frequencyHz: String
    public var receiveBand: String
    public var rstSent: String
    public var rstReceived: String
    public var gridSquare: String
    public var name: String
    public var note: String
    public var qth: String
    public var state: String
    public var county: String
    public var iota: String
    public var qslVia: String
    public var power: String
    public var cqZone: String
    public var ituZone: String
    public var propagationMode: String
    public var satelliteName: String
    public var satelliteMode: String
    public var sotaReference: String
    public var potaReference: String
    public var wwffReference: String

    private enum CodingKeys: String, CodingKey {
        case call, qsoDate, timeOn, band, mode, frequencyHz, receiveBand
        case rstSent, rstReceived, gridSquare, name, note, qth, state, county
        case iota, qslVia, power, cqZone, ituZone, propagationMode
        case satelliteName, satelliteMode, sotaReference, potaReference, wwffReference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        call = try container.decode(String.self, forKey: .call)
        qsoDate = try container.decode(String.self, forKey: .qsoDate)
        timeOn = try container.decode(String.self, forKey: .timeOn)
        band = try container.decode(String.self, forKey: .band)
        mode = try container.decode(String.self, forKey: .mode)
        frequencyHz = try container.decode(String.self, forKey: .frequencyHz)
        receiveBand = try container.decodeIfPresent(String.self, forKey: .receiveBand) ?? ""
        rstSent = try container.decode(String.self, forKey: .rstSent)
        rstReceived = try container.decode(String.self, forKey: .rstReceived)
        gridSquare = try container.decode(String.self, forKey: .gridSquare)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decode(String.self, forKey: .note)
        qth = try container.decode(String.self, forKey: .qth)
        state = try container.decode(String.self, forKey: .state)
        county = try container.decode(String.self, forKey: .county)
        iota = try container.decode(String.self, forKey: .iota)
        qslVia = try container.decode(String.self, forKey: .qslVia)
        power = try container.decodeIfPresent(String.self, forKey: .power) ?? ""
        cqZone = try container.decodeIfPresent(String.self, forKey: .cqZone) ?? ""
        ituZone = try container.decodeIfPresent(String.self, forKey: .ituZone) ?? ""
        propagationMode = try container.decode(String.self, forKey: .propagationMode)
        satelliteName = try container.decode(String.self, forKey: .satelliteName)
        satelliteMode = try container.decode(String.self, forKey: .satelliteMode)
        sotaReference = try container.decode(String.self, forKey: .sotaReference)
        potaReference = try container.decode(String.self, forKey: .potaReference)
        wwffReference = try container.decode(String.self, forKey: .wwffReference)
    }

    public init?(adif record: ADIFRecord) {
        guard
            let call = record["CALL"],
            let date = nonEmpty(record["QSO_DATE_OFF"]) ?? nonEmpty(record["QSO_DATE"]),
            let time = nonEmpty(record["TIME_OFF"]) ?? nonEmpty(record["TIME_ON"]),
            let band = record["BAND"],
            let mode = nonEmpty(record["SUBMODE"]) ?? nonEmpty(record["MODE"])
        else { return nil }
        self.call = normalized(call, uppercased: true)
        qsoDate = digits(date, count: 8)
        timeOn = normalizedTime(time)
        self.band = normalized(band).lowercased()
        self.mode = normalized(mode, uppercased: true)
        frequencyHz = frequencyFromMHz(record["FREQ"])
        receiveBand = normalized(record["BAND_RX"]).lowercased()
        rstSent = normalized(record["RST_SENT"])
        rstReceived = normalized(record["RST_RCVD"])
        gridSquare = normalized(record["GRIDSQUARE"], uppercased: true)
        name = normalized(record["NAME"])
        note = normalized(nonEmpty(record["COMMENT"]) ?? record["NOTES"])
        qth = normalized(record["QTH"])
        state = normalized(record["STATE"], uppercased: true)
        county = normalized(record["CNTY"])
        iota = normalized(record["IOTA"], uppercased: true)
        qslVia = normalized(record["QSL_VIA"])
        power = normalized(record["TX_PWR"])
        cqZone = normalized(record["CQZ"])
        ituZone = normalized(record["ITUZ"])
        propagationMode = normalized(record["PROP_MODE"], uppercased: true)
        satelliteName = normalized(record["SAT_NAME"], uppercased: true)
        satelliteMode = normalized(record["SAT_MODE"], uppercased: true)
        sotaReference = normalized(record["SOTA_REF"], uppercased: true)
        potaReference = normalized(record["POTA_REF"], uppercased: true)
        wwffReference = normalized(record["WWFF_REF"], uppercased: true)
    }

    public init?(wavelog qso: WavelogQSO) {
        let dateParts = qso.qsoDate.split(separator: " ", maxSplits: 1).map(String.init)
        guard dateParts.count == 2 else { return nil }
        call = normalized(qso.call, uppercased: true)
        qsoDate = dateParts[0].replacingOccurrences(of: "-", with: "")
        timeOn = normalizedTime(dateParts[1])
        band = normalized(qso.band).lowercased()
        mode = normalized(nonEmpty(qso.submode) ?? qso.mode, uppercased: true)
        frequencyHz = normalizedFrequencyHz(qso.frequency)
        receiveBand = normalized(qso.receiveBand).lowercased()
        rstSent = normalized(qso.rstSent)
        rstReceived = normalized(qso.rstReceived)
        gridSquare = normalized(qso.gridSquare, uppercased: true)
        name = normalized(qso.name)
        note = normalized(nonEmpty(qso.comment) ?? qso.notes)
        qth = normalized(qso.qth)
        state = normalized(qso.state, uppercased: true)
        county = normalized(qso.county)
        iota = normalized(qso.iota, uppercased: true)
        qslVia = normalized(qso.qslVia)
        power = normalized(qso.power)
        cqZone = normalized(qso.cqZone)
        ituZone = normalized(qso.ituZone)
        propagationMode = normalized(qso.propagationMode, uppercased: true)
        satelliteName = normalized(qso.satelliteName, uppercased: true)
        satelliteMode = normalized(qso.satelliteMode, uppercased: true)
        sotaReference = normalized(qso.sotaReference, uppercased: true)
        potaReference = normalized(qso.potaReference, uppercased: true)
        wwffReference = normalized(qso.wwffReference, uppercased: true)
    }

    public var semanticIdentityHash: String {
        SemanticQSOIdentity(
            call: call,
            timestamp: qsoDate + timeOn,
            band: band,
            mode: mode,
            frequency: frequencyHz
        ).sha256
    }

    public var contentHash: String {
        let values = [
            call, qsoDate, timeOn, band, mode, frequencyHz, receiveBand, rstSent, rstReceived,
            gridSquare, name, note, qth, state, county, iota, qslVia,
            power, cqZone, ituZone, satelliteName, satelliteMode,
        ]
        return SHA256.hash(data: Data(values.joined(separator: "\u{001F}").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public var nonIdentityContentHash: String {
        let values = [
            frequencyHz, receiveBand, rstSent, rstReceived, gridSquare, name, note, qth, state,
            county, iota, qslVia, power, cqZone, ituZone, satelliteName, satelliteMode,
        ]
        return SHA256.hash(data: Data(values.joined(separator: "\u{001F}").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public var identityComponents: [String] { [call, qsoDate + timeOn, band, mode] }

    public func supportedChanges(from previous: Self) -> [String: String] {
        var changes: [String: String] = [:]
        func record(_ key: String, _ current: String, _ old: String) {
            if current != old { changes[key] = current }
        }
        record("call", call, previous.call)
        record("qsoDate", qsoDate, previous.qsoDate)
        record("timeOn", timeOn, previous.timeOn)
        record("band", band, previous.band)
        record("mode", mode, previous.mode)
        record("frequencyHz", frequencyHz, previous.frequencyHz)
        record("receiveBand", receiveBand, previous.receiveBand)
        record("rstSent", rstSent, previous.rstSent)
        record("rstReceived", rstReceived, previous.rstReceived)
        record("gridSquare", gridSquare, previous.gridSquare)
        record("name", name, previous.name)
        record("note", note, previous.note)
        record("qth", qth, previous.qth)
        record("state", state, previous.state)
        record("county", county, previous.county)
        record("iota", iota, previous.iota)
        record("qslVia", qslVia, previous.qslVia)
        record("power", power, previous.power)
        record("cqZone", cqZone, previous.cqZone)
        record("ituZone", ituZone, previous.ituZone)
        record("satelliteName", satelliteName, previous.satelliteName)
        record("satelliteMode", satelliteMode, previous.satelliteMode)
        return changes
    }

    public func identityDifferenceCount(from other: Self) -> Int {
        zip(identityComponents, other.identityComponents).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
    }

    public func applying(to record: ADIFRecord) -> ADIFRecord {
        var fields = record.fields
        fields["CALL"] = call
        fields["QSO_DATE"] = qsoDate
        fields["QSO_DATE_OFF"] = qsoDate
        fields["TIME_ON"] = timeOn
        fields["TIME_OFF"] = timeOn
        fields["BAND"] = band
        fields["BAND_RX"] = receiveBand
        fields["MODE"] = mode
        fields.removeValue(forKey: "SUBMODE")
        if !frequencyHz.isEmpty, let hz = Double(frequencyHz) {
            fields["FREQ"] = String(format: "%.6f", hz / 1_000_000)
        }
        fields["RST_SENT"] = rstSent
        fields["RST_RCVD"] = rstReceived
        fields["GRIDSQUARE"] = gridSquare
        fields["NAME"] = name
        fields["COMMENT"] = note
        fields["QTH"] = qth
        fields["STATE"] = state
        fields["CNTY"] = county
        fields["IOTA"] = iota
        fields["QSL_VIA"] = qslVia
        fields["TX_PWR"] = power
        fields["CQZ"] = cqZone
        fields["ITUZ"] = ituZone
        fields["PROP_MODE"] = propagationMode
        fields["SAT_NAME"] = satelliteName
        fields["SAT_MODE"] = satelliteMode
        fields["SOTA_REF"] = sotaReference
        fields["POTA_REF"] = potaReference
        fields["WWFF_REF"] = wwffReference
        return ADIFRecord(fields: fields)
    }

    public var wavelogUpdate: WavelogQSOUpdate {
        var update = WavelogQSOUpdate()
        update.call = call
        update.band = band
        update.mode = mode
        update.qsoDate = "\(qsoDate.prefix(4))-\(qsoDate.dropFirst(4).prefix(2))-\(qsoDate.suffix(2))"
        update.timeOn = timeOn
        update.frequency = Int64(frequencyHz)
        update.receiveBand = receiveBand
        update.rstSent = rstSent
        update.rstReceived = rstReceived
        update.gridSquare = gridSquare
        update.name = name
        update.comment = note
        update.qth = qth
        update.state = state
        update.county = county
        update.iota = iota
        update.qslVia = qslVia
        update.power = power
        update.cqZone = cqZone
        update.ituZone = ituZone
        update.satelliteName = satelliteName
        update.satelliteMode = satelliteMode
        return update
    }

    public func wavelogUpdate(changesFrom previous: Self) -> WavelogQSOUpdate {
        var update = WavelogQSOUpdate()
        if call != previous.call { update.call = call }
        if band != previous.band { update.band = band }
        if mode != previous.mode { update.mode = mode }
        if qsoDate != previous.qsoDate || timeOn != previous.timeOn {
            update.qsoDate = "\(qsoDate.prefix(4))-\(qsoDate.dropFirst(4).prefix(2))-\(qsoDate.suffix(2))"
            update.timeOn = timeOn
        }
        if frequencyHz != previous.frequencyHz { update.frequency = Int64(frequencyHz) }
        if receiveBand != previous.receiveBand { update.receiveBand = receiveBand }
        if rstSent != previous.rstSent { update.rstSent = rstSent }
        if rstReceived != previous.rstReceived { update.rstReceived = rstReceived }
        if gridSquare != previous.gridSquare { update.gridSquare = gridSquare }
        if name != previous.name { update.name = name }
        if note != previous.note { update.comment = note }
        if qth != previous.qth { update.qth = qth }
        if state != previous.state { update.state = state }
        if county != previous.county { update.county = county }
        if iota != previous.iota { update.iota = iota }
        if qslVia != previous.qslVia { update.qslVia = qslVia }
        if power != previous.power { update.power = power }
        if cqZone != previous.cqZone { update.cqZone = cqZone }
        if ituZone != previous.ituZone { update.ituZone = ituZone }
        if satelliteName != previous.satelliteName { update.satelliteName = satelliteName }
        if satelliteMode != previous.satelliteMode { update.satelliteMode = satelliteMode }
        return update
    }

    public func mergingChanges(from previousSource: Self, to currentSource: Self) -> Self {
        var result = self
        if currentSource.call != previousSource.call { result.call = currentSource.call }
        if currentSource.qsoDate != previousSource.qsoDate { result.qsoDate = currentSource.qsoDate }
        if currentSource.timeOn != previousSource.timeOn { result.timeOn = currentSource.timeOn }
        if currentSource.band != previousSource.band { result.band = currentSource.band }
        if currentSource.mode != previousSource.mode { result.mode = currentSource.mode }
        if currentSource.frequencyHz != previousSource.frequencyHz { result.frequencyHz = currentSource.frequencyHz }
        if currentSource.receiveBand != previousSource.receiveBand { result.receiveBand = currentSource.receiveBand }
        if currentSource.rstSent != previousSource.rstSent { result.rstSent = currentSource.rstSent }
        if currentSource.rstReceived != previousSource.rstReceived { result.rstReceived = currentSource.rstReceived }
        if currentSource.gridSquare != previousSource.gridSquare { result.gridSquare = currentSource.gridSquare }
        if currentSource.name != previousSource.name { result.name = currentSource.name }
        if currentSource.note != previousSource.note { result.note = currentSource.note }
        if currentSource.qth != previousSource.qth { result.qth = currentSource.qth }
        if currentSource.state != previousSource.state { result.state = currentSource.state }
        if currentSource.county != previousSource.county { result.county = currentSource.county }
        if currentSource.iota != previousSource.iota { result.iota = currentSource.iota }
        if currentSource.qslVia != previousSource.qslVia { result.qslVia = currentSource.qslVia }
        if currentSource.power != previousSource.power { result.power = currentSource.power }
        if currentSource.cqZone != previousSource.cqZone { result.cqZone = currentSource.cqZone }
        if currentSource.ituZone != previousSource.ituZone { result.ituZone = currentSource.ituZone }
        if currentSource.satelliteName != previousSource.satelliteName { result.satelliteName = currentSource.satelliteName }
        if currentSource.satelliteMode != previousSource.satelliteMode { result.satelliteMode = currentSource.satelliteMode }
        return result
    }

    public func baseliningNewlySupportedFields(from current: Self) -> Self {
        var result = self
        result.receiveBand = current.receiveBand
        result.power = current.power
        result.cqZone = current.cqZone
        result.ituZone = current.ituZone
        return result
    }
}

public struct ReconciliationLink: Codable, Equatable, Sendable {
    public var wavelogID: Int
    public var rumlogRowID: Int64?
    public var semanticIdentityHash: String
    public var rumlogSnapshot: QSOEditableSnapshot
    public var wavelogSnapshot: QSOEditableSnapshot
    public var rumlogContentHash: String
    public var wavelogContentHash: String

    public init(wavelogID: Int, rumlogRowID: Int64? = nil, local: QSOEditableSnapshot, remote: QSOEditableSnapshot) {
        self.wavelogID = wavelogID
        self.rumlogRowID = rumlogRowID
        semanticIdentityHash = local.semanticIdentityHash
        rumlogSnapshot = local
        wavelogSnapshot = remote
        rumlogContentHash = local.contentHash
        wavelogContentHash = remote.contentHash
    }
}

public enum ReconciliationDecision: Equatable, Sendable {
    case unchanged
    case alignBaselines
    case updateWavelog
    case updateRumlog
    case conflict
}

public func reconciliationDecision(
    link: ReconciliationLink,
    local: QSOEditableSnapshot,
    remote: QSOEditableSnapshot
) -> ReconciliationDecision {
    let localChanged = local.contentHash != link.rumlogContentHash
    let remoteChanged = remote.contentHash != link.wavelogContentHash
    if local.contentHash == remote.contentHash, localChanged || remoteChanged { return .alignBaselines }
    if localChanged && remoteChanged {
        let localChanges = local.supportedChanges(from: link.rumlogSnapshot)
        let remoteChanges = remote.supportedChanges(from: link.wavelogSnapshot)
        return !localChanges.isEmpty && localChanges == remoteChanges ? .alignBaselines : .conflict
    }
    if localChanged { return .updateWavelog }
    if remoteChanged { return .updateRumlog }
    return .unchanged
}

public struct ReconciliationState: Codable, Equatable, Sendable {
    public var stationID: Int
    public var links: [Int: ReconciliationLink]
    public var lastRunAt: Date?
    public var localSnapshotVersion: Int?

    public init(
        stationID: Int,
        links: [Int: ReconciliationLink] = [:],
        lastRunAt: Date? = nil,
        localSnapshotVersion: Int? = RumlogSQLiteReader.snapshotVersion
    ) {
        self.stationID = stationID
        self.links = links
        self.lastRunAt = lastRunAt
        self.localSnapshotVersion = localSnapshotVersion
    }
}

private func normalized(_ value: String?, uppercased: Bool = false) -> String {
    let result = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return uppercased ? result.uppercased() : result
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}

private func digits(_ value: String, count: Int) -> String {
    String(value.filter(\.isNumber).prefix(count))
}

private func normalizedTime(_ value: String) -> String {
    let value = value.filter(\.isNumber)
    return String((value + "000000").prefix(6))
}

private func frequencyFromMHz(_ value: String?) -> String {
    guard let value, let mhz = Double(value.replacingOccurrences(of: ",", with: ".")) else { return "" }
    return String(Int64((mhz * 1_000_000).rounded()))
}

private func normalizedFrequencyHz(_ value: String?) -> String {
    guard let value, let hz = Double(value.replacingOccurrences(of: ",", with: ".")) else { return "" }
    return String(Int64(hz.rounded()))
}
