import Foundation
@testable import MaverickBroadcast
import MaverickModels
import XCTest

final class FileStateStoreTests: XCTestCase {
    func testEncryptedLocalStateRoundTripsAndRestoresEarlierRevision() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("maverick-file-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = BroadcastingStateConfig(
            type: "local",
            encryptionKeySecret: "encryption",
            path: root.path
        )
        let store = try FileStateStore(
            configuration: configuration,
            secrets: TestSecrets(values: ["encryption": "correct horse battery staple"])
        )

        let first = Ledger(revision: 1, initializedAt: Date(timeIntervalSince1970: 100))
        let firstSnapshot = try await store.commit(first)
        let second = Ledger(revision: 2, initializedAt: Date(timeIntervalSince1970: 200))
        _ = try await store.commit(second)

        guard case .loaded(let loaded, let latest) = try await store.load() else {
            return XCTFail("Expected initialized local state")
        }
        XCTAssertEqual(loaded.revision, 2)
        XCTAssertEqual(latest.revision, 2)
        let snapshots = try await store.snapshots()
        XCTAssertEqual(snapshots.map(\.revision), [2, 1])
        let restored = try await store.restore(firstSnapshot)
        XCTAssertEqual(restored.revision, 1)

        let encrypted = try Data(contentsOf: root.appendingPathComponent(firstSnapshot.key))
        XCTAssertFalse(String(data: encrypted, encoding: .utf8)?.contains("initializedAt") == true)
    }

    func testWrongKeyAndMissingPointerWithSnapshotsFailClosed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("maverick-file-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = BroadcastingStateConfig(
            type: "local",
            encryptionKeySecret: "encryption",
            path: root.path
        )
        let store = try FileStateStore(
            configuration: configuration,
            secrets: TestSecrets(values: ["encryption": "original key"])
        )
        _ = try await store.commit(Ledger(revision: 1))

        let wrongKeyStore = try FileStateStore(
            configuration: configuration,
            secrets: TestSecrets(values: ["encryption": "wrong key"])
        )
        do {
            _ = try await wrongKeyStore.load()
            XCTFail("A wrong encryption key must fail closed")
        } catch {}

        try FileManager.default.removeItem(at: root.appendingPathComponent("latest.json"))
        do {
            _ = try await store.load()
            XCTFail("Snapshots without the latest pointer must not look like a fresh ledger")
        } catch {}
    }
}

private struct TestSecrets: SecretResolver {
    let values: [String: String]

    func resolve(_ reference: String) throws -> String {
        guard let value = values[reference] else {
            throw ProviderFailure.configuration("Missing test secret: \(reference)")
        }
        return value
    }
}
