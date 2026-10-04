import Darwin
import Foundation

public struct UDPDatagram: Sendable {
    public let data: Data
    public let sourceAddress: String
    public let sourcePort: UInt16
    public let receivedAt: Date
}

public enum UDPListenerError: Error, LocalizedError {
    case invalidAddress(String)
    case invalidPort(UInt16)
    case systemCall(operation: String, code: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidAddress(address):
            return "Invalid IPv4 bind address: \(address)"
        case let .invalidPort(port):
            return "Invalid UDP port: \(port)"
        case let .systemCall(operation, code, message):
            return "\(operation) failed (errno \(code)): \(message)"
        }
    }
}

public final class UDPDatagramListener {
    private let bindAddress: String
    private let port: UInt16
    private let receiveBufferSize: Int

    public init(bindAddress: String = "0.0.0.0", port: UInt16, receiveBufferSize: Int = 65_535) {
        self.bindAddress = bindAddress
        self.port = port
        self.receiveBufferSize = max(1_024, min(receiveBufferSize, 65_535))
    }

    public func run(
        maxPackets: Int? = nil,
        idleTimeout: TimeInterval? = nil,
        onDatagram: (UDPDatagram) throws -> Void
    ) throws {
        guard port > 0 else { throw UDPListenerError.invalidPort(port) }

        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, Int32(IPPROTO_UDP))
        guard descriptor >= 0 else { throw systemError("socket") }
        defer { Darwin.close(descriptor) }

        var reuse: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse))) == 0 else {
            throw systemError("setsockopt(SO_REUSEADDR)")
        }

        if let idleTimeout {
            var timeout = timeval(
                tv_sec: Int(idleTimeout),
                tv_usec: Int32((idleTimeout - floor(idleTimeout)) * 1_000_000)
            )
            guard setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0 else {
                throw systemError("setsockopt(SO_RCVTIMEO)")
            }
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        if bindAddress == "0.0.0.0" {
            address.sin_addr = in_addr(s_addr: INADDR_ANY)
        } else {
            let parsed = bindAddress.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
            guard parsed == 1 else { throw UDPListenerError.invalidAddress(bindAddress) }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw systemError("bind") }

        var received = 0
        while maxPackets.map({ received < $0 }) ?? true {
            var buffer = [UInt8](repeating: 0, count: receiveBufferSize)
            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)

            let byteCount = withUnsafeMutablePointer(to: &source) { sourcePointer in
                sourcePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundSource in
                    buffer.withUnsafeMutableBytes { bytes in
                        Darwin.recvfrom(
                            descriptor,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            reboundSource,
                            &sourceLength
                        )
                    }
                }
            }

            if byteCount < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                if errno == EINTR {
                    continue
                }
                throw systemError("recvfrom")
            }

            let datagram = UDPDatagram(
                data: Data(buffer.prefix(byteCount)),
                sourceAddress: formatAddress(source),
                sourcePort: UInt16(bigEndian: source.sin_port),
                receivedAt: Date()
            )
            try onDatagram(datagram)
            received += 1
        }
    }

    private func formatAddress(_ address: sockaddr_in) -> String {
        var mutableAddress = address.sin_addr
        var output = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let result = inet_ntop(AF_INET, &mutableAddress, &output, socklen_t(INET_ADDRSTRLEN))
        guard result != nil else { return "unknown" }
        let bytes = output.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func systemError(_ operation: String) -> UDPListenerError {
        let code = errno
        return .systemCall(operation: operation, code: code, message: String(cString: strerror(code)))
    }
}
