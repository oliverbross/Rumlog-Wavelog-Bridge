import BridgeCore
import Foundation

private struct Options {
    var bindAddress = "0.0.0.0"
    var port: UInt16 = 12_060
    var outputPath: String?
    var includeRaw = false
    var maxPackets: Int?
    var timeout: TimeInterval?

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--bind":
                index += 1
                options.bindAddress = try value(arguments, index, for: argument)
            case "--port":
                index += 1
                let raw = try value(arguments, index, for: argument)
                guard let port = UInt16(raw), port > 0 else { throw ArgumentError("Invalid port: \(raw)") }
                options.port = port
            case "--output":
                index += 1
                options.outputPath = try value(arguments, index, for: argument)
            case "--include-raw":
                options.includeRaw = true
            case "--max-packets":
                index += 1
                let raw = try value(arguments, index, for: argument)
                guard let count = Int(raw), count > 0 else { throw ArgumentError("Invalid packet count: \(raw)") }
                options.maxPackets = count
            case "--timeout":
                index += 1
                let raw = try value(arguments, index, for: argument)
                guard let timeout = TimeInterval(raw), timeout > 0 else { throw ArgumentError("Invalid timeout: \(raw)") }
                options.timeout = timeout
            case "--help", "-h":
                printUsage()
                Foundation.exit(EXIT_SUCCESS)
            default:
                throw ArgumentError("Unknown argument: \(argument)")
            }
            index += 1
        }
        return options
    }

    private static func value(_ arguments: [String], _ index: Int, for option: String) throws -> String {
        guard index < arguments.count else { throw ArgumentError("Missing value for \(option)") }
        return arguments[index]
    }
}

private struct ArgumentError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private final class CaptureSink {
    private let encoder: JSONEncoder
    private let output: FileHandle

    init(path: String?) throws {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        if let path {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            output = try FileHandle(forWritingTo: url)
            try output.seekToEnd()
        } else {
            output = .standardOutput
        }
    }

    deinit {
        if output !== FileHandle.standardOutput {
            try? output.close()
        }
    }

    func write(_ record: RumlogCaptureRecord) throws {
        var data = try encoder.encode(record)
        data.append(0x0A)
        try output.write(contentsOf: data)
    }
}

private func printUsage() {
    print("""
    Usage: rumlog-probe [options]

      --bind ADDRESS       IPv4 bind address (default: 0.0.0.0)
      --port PORT          UDP port (default: 12060; verify in RUMlog)
      --output PATH        Append NDJSON records to PATH
      --include-raw        Include raw XML in records
      --max-packets COUNT  Exit after COUNT datagrams
      --timeout SECONDS    Exit after an idle timeout
      --help               Show this help
    """)
}

do {
    let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    let sink = try CaptureSink(path: options.outputPath)
    let parser = RumlogXMLParser()
    let listener = UDPDatagramListener(bindAddress: options.bindAddress, port: options.port)
    var sequence: UInt64 = 0

    FileHandle.standardError.write(
        Data("Listening for RUMlog UDP on \(options.bindAddress):\(options.port)…\n".utf8)
    )

    try listener.run(maxPackets: options.maxPackets, idleTimeout: options.timeout) { datagram in
        sequence += 1
        let message: RumlogPeerMessage?
        let parseError: String?
        do {
            message = try parser.parse(datagram.data)
            parseError = nil
        } catch {
            message = nil
            parseError = error.localizedDescription
        }

        let rawXML = options.includeRaw ? String(data: datagram.data, encoding: .utf8) : nil
        try sink.write(
            RumlogCaptureRecord(
                sequence: sequence,
                receivedAt: datagram.receivedAt,
                sourceAddress: datagram.sourceAddress,
                sourcePort: datagram.sourcePort,
                byteCount: datagram.data.count,
                message: message,
                parseError: parseError,
                rawXML: rawXML
            )
        )
    }
} catch {
    FileHandle.standardError.write(Data("rumlog-probe: \(error.localizedDescription)\n".utf8))
    printUsage()
    Foundation.exit(EXIT_FAILURE)
}
