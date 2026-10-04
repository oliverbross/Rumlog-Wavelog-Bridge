import Foundation

public enum RumlogXMLParserError: Error, LocalizedError, Equatable {
    case emptyDocument
    case malformedXML(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "The datagram did not contain an XML root element."
        case let .malformedXML(message):
            return "Malformed RUMlog XML: \(message)"
        }
    }
}

public struct RumlogXMLParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> RumlogPeerMessage {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "unknown parser error"
            throw RumlogXMLParserError.malformedXML(message)
        }
        guard let root = delegate.rootElement else {
            throw RumlogXMLParserError.emptyDocument
        }
        return RumlogPeerMessage(rootElement: root, fields: delegate.fields)
    }
}

private final class Delegate: NSObject, XMLParserDelegate {
    var rootElement: String?
    var fields: [String: String] = [:]

    private var depth = 0
    private var currentField: String?
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if depth == 0 {
            rootElement = elementName.lowercased()
        } else if depth == 1 {
            currentField = elementName.lowercased()
            currentText = ""
        }
        depth += 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentField != nil else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        depth -= 1
        guard depth == 1, currentField == elementName.lowercased() else { return }
        fields[currentField!] = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentField = nil
        currentText = ""
    }
}
