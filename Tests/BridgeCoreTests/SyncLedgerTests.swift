import Foundation
import Testing
@testable import BridgeCore

@Test func ledgerPersistsLinksAndDeduplicatesOutbox() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("ledger.json")

    let ledger = try SyncLedger(fileURL: file)
    let link = ContactLink(
        rumlogID: "rumlog-guid",
        wavelogID: 42,
        semanticIdentityHash: "identity"
    )
    try await ledger.upsert(link)

    let operation = PendingOperation(
        direction: .rumlogToWavelog,
        kind: .create,
        rumlogID: "rumlog-guid",
        payloadHash: "payload"
    )
    let firstID = try await ledger.enqueue(operation)
    let duplicateID = try await ledger.enqueue(operation)
    #expect(firstID == duplicateID)

    let reloaded = try SyncLedger(fileURL: file)
    #expect(await reloaded.contactLink(rumlogID: "rumlog-guid") == link)
    #expect(await reloaded.pendingOperations().count == 1)

    try await reloaded.mark(
        operationID: firstID,
        state: .deliveryUnknown,
        error: "lost acknowledgement",
        incrementAttempts: true
    )
    let pending = await reloaded.pendingOperations()
    #expect(pending.first?.state == .deliveryUnknown)
    #expect(pending.first?.attempts == 1)
}
