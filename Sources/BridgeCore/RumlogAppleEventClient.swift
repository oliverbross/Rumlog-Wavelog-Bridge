import AppKit
import Foundation

public enum RumlogAppleEventError: Error, LocalizedError {
    case notInstalled
    case notRunning
    case multipleInstances(Int)
    case eventFailed(number: Int, message: String)
    case invalidReply
    case logbookMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: return "RUMlogNG is not installed in /Applications."
        case .notRunning: return "RUMlogNG is not running. Open the target logbook first."
        case let .multipleInstances(count):
            return "\(count) RUMlogNG instances are running. Close extras so the target logbook is unambiguous."
        case let .eventFailed(number, message): return "RUMlogNG Apple event failed (\(number)): \(message)"
        case .invalidReply: return "RUMlogNG returned an invalid Apple event reply."
        case let .logbookMismatch(path):
            return "The selected logbook does not match the logbook open in RUMlogNG: \(path)"
        }
    }
}

public struct RumlogAppleEventClient: @unchecked Sendable {
    public let bundleIdentifier: String

    public init(bundleIdentifier: String = "de.dl2rum.RUMlogNG") {
        self.bundleIdentifier = bundleIdentifier
    }

    public func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    public func isRunning() -> Bool {
        runningInstanceCount() > 0
    }

    public func runningInstanceCount() -> Int {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).count
    }

    public func importADIF(_ adif: String, timeout: TimeInterval = 300) throws {
        _ = try send(eventID: fourCharCode("Adif"), directText: adif, timeout: timeout)
    }

    public func exportADIF(since sqlDateTime: String, timeout: TimeInterval = 120) throws -> String {
        let reply = try send(eventID: fourCharCode("Adi2"), directText: sqlDateTime, timeout: timeout)
        guard let value = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue
            ?? reply.stringValue
        else { throw RumlogAppleEventError.invalidReply }
        return value
    }

    private func send(eventID: AEEventID, directText: String, timeout: TimeInterval) throws -> NSAppleEventDescriptor {
        guard isInstalled() else { throw RumlogAppleEventError.notInstalled }
        let instanceCount = runningInstanceCount()
        guard instanceCount > 0 else { throw RumlogAppleEventError.notRunning }
        guard instanceCount == 1 else { throw RumlogAppleEventError.multipleInstances(instanceCount) }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: fourCharCode("RUMs"),
            eventID: eventID,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(string: directText), forKeyword: AEKeyword(keyDirectObject))
        do {
            let reply = try event.sendEvent(options: [.waitForReply], timeout: timeout)
            if let errorNumber = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value,
               errorNumber != 0 {
                let message = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue
                    ?? "Unknown Apple event error"
                throw RumlogAppleEventError.eventFailed(number: Int(errorNumber), message: message)
            }
            return reply
        } catch {
            if let rumlogError = error as? RumlogAppleEventError { throw rumlogError }
            let ns = error as NSError
            throw RumlogAppleEventError.eventFailed(number: ns.code, message: ns.localizedDescription)
        }
    }
}

private func fourCharCode(_ value: String) -> UInt32 {
    value.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
}
