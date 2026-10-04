import Foundation

public struct ADIFRecord: Equatable, Sendable {
    public var fields: [String: String]

    public init(fields: [String: String]) {
        self.fields = fields.reduce(into: [:]) { $0[$1.key.uppercased()] = $1.value }
    }

    public subscript(_ name: String) -> String? { fields[name.uppercased()] }

    public var semanticIdentityHash: String? {
        guard
            let call = self["CALL"],
            let date = self["QSO_DATE_OFF"]?.nonEmpty ?? self["QSO_DATE"],
            let time = self["TIME_OFF"]?.nonEmpty ?? self["TIME_ON"],
            let band = self["BAND"],
            let mode = self["SUBMODE"]?.nonEmpty ?? self["MODE"]
        else { return nil }
        return SemanticQSOIdentity(
            call: call,
            timestamp: date + time,
            band: band,
            mode: mode,
            frequency: self["FREQ"] ?? ""
        ).sha256
    }

    public var adifDocument: String {
        let body = fields.keys.sorted().map { key in
            let value = fields[key] ?? ""
            return "<\(key):\(value.utf8.count)>\(value)"
        }.joined()
        return "<ADIF_VER:5>3.1.7<EOH>\r\n\(body)<EOR>\r\n"
    }
}

public struct ADIFParser: Sendable {
    public init() {}

    public func records(in text: String) -> [ADIFRecord] {
        let upper = text.uppercased()
        let bodyStart = upper.range(of: "<EOH>")?.upperBound ?? text.startIndex
        var records: [ADIFRecord] = []
        var fields: [String: String] = [:]
        var cursor = bodyStart

        while let open = text[cursor...].firstIndex(of: "<") {
            guard let close = text[open...].firstIndex(of: ">") else { break }
            let descriptor = String(text[text.index(after: open)..<close])
            let parts = descriptor.split(separator: ":", maxSplits: 2).map(String.init)
            let name = parts[0].uppercased()
            cursor = text.index(after: close)
            if name == "EOR" {
                if !fields.isEmpty { records.append(ADIFRecord(fields: fields)) }
                fields.removeAll(keepingCapacity: true)
                continue
            }
            guard parts.count >= 2, let length = Int(parts[1]), length >= 0 else { continue }
            guard let end = text.index(cursor, offsetBy: length, limitedBy: text.endIndex) else { break }
            fields[name] = String(text[cursor..<end])
            cursor = end
        }
        return records
    }

    public func removingKnownRecords(
        from text: String,
        knownFingerprints: Set<String>
    ) -> (adif: String, records: [ADIFRecord]) {
        guard let eoh = text.range(of: "<EOH>", options: .caseInsensitive) else {
            let parsed = records(in: text)
            let retained = parsed.filter { record in
                guard let hash = record.semanticIdentityHash else { return true }
                return !knownFingerprints.contains(hash)
            }
            return retained.count == parsed.count ? (text, retained) : ("", retained)
        }

        var output = String(text[..<eoh.upperBound]) + "\r\n"
        var retained: [ADIFRecord] = []
        var cursor = eoh.upperBound
        while let eor = text.range(of: "<EOR>", options: .caseInsensitive, range: cursor..<text.endIndex) {
            let block = String(text[cursor..<eor.upperBound])
            if let record = records(in: block).first {
                let isKnown = record.semanticIdentityHash.map(knownFingerprints.contains) ?? false
                if !isKnown {
                    output += block + "\r\n"
                    retained.append(record)
                }
            }
            cursor = eor.upperBound
        }
        return (output, retained)
    }
}

public extension WavelogQSOCreate {
    init?(adif record: ADIFRecord) {
        guard
            let call = record["CALL"]?.nonEmpty,
            let band = record["BAND"]?.nonEmpty,
            let mode = record["MODE"]?.nonEmpty,
            let rawDate = record["QSO_DATE"], rawDate.count == 8,
            let time = record["TIME_ON"]?.nonEmpty
        else { return nil }
        let date = "\(rawDate.prefix(4))-\(rawDate.dropFirst(4).prefix(2))-\(rawDate.suffix(2))"
        self.init(call: call, band: band.lowercased(), mode: mode, qsoDate: date, timeOn: time)
        if let mhz = record["FREQ"].flatMap(Double.init) {
            frequency = Int64((mhz * 1_000_000).rounded())
        }
        rstSent = record["RST_SENT"]
        rstReceived = record["RST_RCVD"]
        gridSquare = record["GRIDSQUARE"]
        name = record["NAME"]
        comment = record["COMMENT"]
        notes = record["NOTES"]
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
