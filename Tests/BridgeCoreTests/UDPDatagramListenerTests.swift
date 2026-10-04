import Darwin
import Foundation
import Testing
@testable import BridgeCore

@Test func receivesLoopbackDatagram() async throws {
    let port: UInt16 = 19_261
    let payload = Data("<appinfo><app>RUMlogNG</app></appinfo>".utf8)

    let receiveTask = Task.detached { () throws -> UDPDatagram? in
        let listener = UDPDatagramListener(bindAddress: "127.0.0.1", port: port)
        var captured: UDPDatagram?
        try listener.run(maxPackets: 1, idleTimeout: 2) { datagram in
            captured = datagram
        }
        return captured
    }

    try await Task.sleep(for: .milliseconds(100))
    try sendUDP(payload, port: port)

    let datagram = try await receiveTask.value
    #expect(datagram?.data == payload)
    #expect(datagram?.sourceAddress == "127.0.0.1")
}

private func sendUDP(_ data: Data, port: UInt16) throws {
    let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, Int32(IPPROTO_UDP))
    guard descriptor >= 0 else { throw POSIXError(.EIO) }
    defer { Darwin.close(descriptor) }

    var destination = sockaddr_in()
    destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    destination.sin_family = sa_family_t(AF_INET)
    destination.sin_port = port.bigEndian
    let parsed = "127.0.0.1".withCString { inet_pton(AF_INET, $0, &destination.sin_addr) }
    guard parsed == 1 else { throw POSIXError(.EINVAL) }

    let sent = withUnsafePointer(to: &destination) { destinationPointer in
        destinationPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            data.withUnsafeBytes { bytes in
                Darwin.sendto(
                    descriptor,
                    bytes.baseAddress,
                    bytes.count,
                    0,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
    }
    guard sent == data.count else { throw POSIXError(.EIO) }
}
