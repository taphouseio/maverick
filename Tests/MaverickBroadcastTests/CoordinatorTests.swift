import Foundation
@testable import MaverickBroadcast
import MaverickModels
import XCTest

final class CoordinatorTests: XCTestCase {
    func testInitializationObservesExistingPostsAndNewPostsDeliverOnce() async throws {
        let store = MemoryStore()
        let recorder = ProviderRecorder()
        let provider = TestProvider(id: "test", recorder: recorder)
        let coordinator = try Coordinator(configuration: config(enabled: true), store: store, providers: [provider])
        await coordinator.start()

        let existing = post(url: "https://example.com/existing", date: Date(timeIntervalSince1970: 100))
        try await coordinator.initialize(with: [existing])
        var snapshot = await coordinator.ledgerSnapshot()
        XCTAssertEqual(snapshot?.posts[existing.identifier]?.deliveries["test"]?.status, .observed)

        let new = post(url: "https://example.com/new", date: Date(timeIntervalSince1970: 300))
        await coordinator.observe([existing, new])
        snapshot = await coordinator.ledgerSnapshot()
        var sendCount = await recorder.sendCount
        XCTAssertEqual(snapshot?.posts[new.identifier]?.deliveries["test"]?.status, .delivered)
        XCTAssertEqual(sendCount, 1)

        let edited = post(url: new.identifier, date: new.publicationDate, description: "Edited")
        await coordinator.observe([existing, edited])
        sendCount = await recorder.sendCount
        XCTAssertEqual(sendCount, 1)
    }

    func testMicropostsAreSkipped() async throws {
        let store = MemoryStore()
        let recorder = ProviderRecorder()
        let coordinator = try Coordinator(
            configuration: config(enabled: true),
            store: store,
            providers: [TestProvider(id: "test", recorder: recorder)]
        )
        await coordinator.start()
        try await coordinator.initialize(with: [])

        let micropost = PostPayload(
            url: URL(string: "https://example.com/micro")!,
            title: nil,
            description: "",
            excerpt: "Short thought",
            tags: [],
            publicationDate: Date(timeIntervalSince1970: 300),
            isMicroblog: true,
            siteTitle: "Example"
        )
        await coordinator.observe([micropost])

        let snapshot = await coordinator.ledgerSnapshot()
        let sendCount = await recorder.sendCount
        XCTAssertEqual(snapshot?.posts[micropost.identifier]?.deliveries["test"]?.status, .skipped)
        XCTAssertEqual(sendCount, 0)
    }

    func testPublicationBoundaryIsInclusive() async throws {
        let recorder = ProviderRecorder()
        let coordinator = try Coordinator(
            configuration: config(enabled: true),
            store: MemoryStore(),
            providers: [TestProvider(id: "test", recorder: recorder)]
        )
        await coordinator.start()
        try await coordinator.initialize(with: [])

        let boundaryPost = post(url: "https://example.com/boundary", date: Date(timeIntervalSince1970: 200))
        await coordinator.observe([boundaryPost])

        let snapshot = await coordinator.ledgerSnapshot()
        let sendCount = await recorder.sendCount
        XCTAssertEqual(snapshot?.posts[boundaryPost.identifier]?.deliveries["test"]?.status, .delivered)
        XCTAssertEqual(sendCount, 1)
    }

    func testDisabledAutomaticPublishingStillAllowsDeliberateBackfill() async throws {
        let recorder = ProviderRecorder()
        let coordinator = try Coordinator(
            configuration: config(enabled: false),
            store: MemoryStore(),
            providers: [TestProvider(id: "test", recorder: recorder)]
        )
        await coordinator.start()
        try await coordinator.initialize(with: [])
        let source = post(url: "https://example.com/manual", date: Date(timeIntervalSince1970: 300))

        await coordinator.observe([source])
        var sendCount = await recorder.sendCount
        XCTAssertEqual(sendCount, 0)

        try await coordinator.backfill(postID: source.identifier, providerIDs: ["test"])
        let snapshot = await coordinator.ledgerSnapshot()
        sendCount = await recorder.sendCount
        XCTAssertEqual(snapshot?.posts[source.identifier]?.deliveries["test"]?.status, .delivered)
        XCTAssertEqual(sendCount, 1)
    }

    func testRecoveredSendingDeliveryBecomesAmbiguous() async throws {
        let source = post(url: "https://example.com/source", date: Date(timeIntervalSince1970: 300))
        var delivery = DeliveryState(status: .sending, now: Date(timeIntervalSince1970: 400))
        delivery.attemptCount = 1
        let postState = PostState(post: source, firstSeenAt: Date(timeIntervalSince1970: 400), deliveries: ["test": delivery])
        let ledger = Ledger(revision: 4, initializedAt: Date(), posts: [source.identifier: postState])
        let store = MemoryStore(initial: ledger)
        let coordinator = try Coordinator(
            configuration: config(enabled: true),
            store: store,
            providers: [TestProvider(id: "test", recorder: ProviderRecorder())]
        )

        await coordinator.start()

        let snapshot = await coordinator.ledgerSnapshot()
        XCTAssertEqual(snapshot?.posts[source.identifier]?.deliveries["test"]?.status, .ambiguous)
        XCTAssertEqual(snapshot?.revision, 5)
    }

    func testExplicitRetryOnlyResendsFailedProvider() async throws {
        let store = MemoryStore()
        let recorder = ProviderRecorder(outcomes: [.transient, .success])
        let coordinator = try Coordinator(
            configuration: config(enabled: true),
            store: store,
            providers: [TestProvider(id: "test", recorder: recorder)]
        )
        await coordinator.start()
        try await coordinator.initialize(with: [])
        let source = post(url: "https://example.com/retry", date: Date(timeIntervalSince1970: 300))

        await coordinator.observe([source])
        var snapshot = await coordinator.ledgerSnapshot()
        XCTAssertEqual(snapshot?.posts[source.identifier]?.deliveries["test"]?.status, .failed)
        try await coordinator.retry(postID: source.identifier, providerID: "test")
        snapshot = await coordinator.ledgerSnapshot()
        let sendCount = await recorder.sendCount
        let idempotencyKeys = await recorder.idempotencyKeys
        XCTAssertEqual(snapshot?.posts[source.identifier]?.deliveries["test"]?.status, .delivered)
        XCTAssertEqual(snapshot?.posts[source.identifier]?.deliveries["test"]?.generation, 0)
        XCTAssertEqual(sendCount, 2)
        XCTAssertEqual(idempotencyKeys.count, 2)
        XCTAssertEqual(Set(idempotencyKeys).count, 1)
    }

    func testDeliberateRebroadcastAdvancesDeliveryGeneration() async throws {
        let recorder = ProviderRecorder(outcomes: [.success, .success])
        let coordinator = try Coordinator(
            configuration: config(enabled: true),
            store: MemoryStore(),
            providers: [TestProvider(id: "test", recorder: recorder)]
        )
        await coordinator.start()
        try await coordinator.initialize(with: [])
        let source = post(url: "https://example.com/rebroadcast", date: Date(timeIntervalSince1970: 300))

        await coordinator.observe([source])
        try await coordinator.explicitlyQueue(postID: source.identifier, providerID: "test")

        let snapshot = await coordinator.ledgerSnapshot()
        let idempotencyKeys = await recorder.idempotencyKeys
        XCTAssertEqual(snapshot?.posts[source.identifier]?.deliveries["test"]?.status, .delivered)
        XCTAssertEqual(snapshot?.posts[source.identifier]?.deliveries["test"]?.generation, 1)
        XCTAssertEqual(idempotencyKeys.count, 2)
        XCTAssertEqual(Set(idempotencyKeys).count, 2)
    }

    func testDuplicateProviderIDsAreRejected() throws {
        let providerConfig = BroadcastingProviderConfig(
            id: "duplicate", type: .mastodon, postTemplate: "{{url}}"
        )
        let configuration = BroadcastingConfig(
            enabled: false,
            autoPublishAfter: .distantFuture,
            state: .init(
                r2: .init(
                    bucket: "test", keyPrefix: "test", accountIDSecret: "a",
                    accessKeyIDSecret: "b", secretAccessKeySecret: "c"
                ),
                encryptionKeySecret: "d"
            ),
            admin: .init(usernameSecret: "u", passwordSecret: "p"),
            providers: [providerConfig, providerConfig]
        )

        XCTAssertThrowsError(
            try Coordinator(configuration: configuration, store: MemoryStore(), providers: [])
        )
    }

    func testDuplicateCanonicalPostURLsAreRejected() async throws {
        let coordinator = try Coordinator(
            configuration: config(enabled: false),
            store: MemoryStore(),
            providers: [TestProvider(id: "test", recorder: ProviderRecorder())]
        )
        await coordinator.start()
        let source = post(url: "https://example.com/duplicate", date: Date())

        do {
            try await coordinator.initialize(with: [source, source])
            XCTFail("Expected duplicate canonical URLs to be rejected")
        } catch let failure as ProviderFailure {
            XCTAssertEqual(failure.localizedDescription, "Duplicate canonical post URL: \(source.identifier)")
        }
    }

    private func config(enabled: Bool) -> BroadcastingConfig {
        BroadcastingConfig(
            enabled: enabled,
            autoPublishAfter: Date(timeIntervalSince1970: 200),
            state: .init(
                r2: .init(
                    bucket: "test", keyPrefix: "test", accountIDSecret: "a",
                    accessKeyIDSecret: "b", secretAccessKeySecret: "c"
                ),
                encryptionKeySecret: "d"
            ),
            admin: .init(usernameSecret: "u", passwordSecret: "p"),
            providers: [.init(id: "test", type: .mastodon, postTemplate: "{{title}} {{url}}")]
        )
    }

    private func post(url: String, date: Date, description: String = "Description") -> PostPayload {
        PostPayload(
            url: URL(string: url)!, title: "Title", description: description, excerpt: "Excerpt",
            tags: [], publicationDate: date, isMicroblog: false, siteTitle: "Example"
        )
    }
}

private actor MemoryStore: StateStore {
    private var ledger: Ledger?
    private var descriptors: [SnapshotDescriptor] = []

    init(initial: Ledger? = nil) {
        ledger = initial
        if let initial {
            descriptors = [.init(revision: initial.revision, key: "\(initial.revision)", checksum: "checksum", createdAt: Date())]
        }
    }

    func load() async throws -> StoreLoadResult {
        guard let ledger, let descriptor = descriptors.last else { return .uninitialized }
        return .loaded(ledger, descriptor)
    }

    func commit(_ ledger: Ledger) async throws -> SnapshotDescriptor {
        self.ledger = ledger
        let descriptor = SnapshotDescriptor(
            revision: ledger.revision, key: "\(ledger.revision)", checksum: "checksum", createdAt: Date()
        )
        descriptors.append(descriptor)
        return descriptor
    }

    func snapshots() async throws -> [SnapshotDescriptor] { descriptors.reversed() }

    func restore(_ snapshot: SnapshotDescriptor) async throws -> Ledger {
        guard let ledger else { throw R2StoreError.invalidSnapshot("missing") }
        return ledger
    }
}

private actor ProviderRecorder {
    enum Outcome: Sendable { case success; case transient }
    private(set) var sendCount = 0
    private(set) var idempotencyKeys: [String] = []
    private var outcomes: [Outcome]

    init(outcomes: [Outcome] = [.success]) { self.outcomes = outcomes }

    func send(_ post: PreparedPost) throws -> DeliveryResult {
        sendCount += 1
        idempotencyKeys.append(post.idempotencyKey)
        let outcome = outcomes.isEmpty ? .success : outcomes.removeFirst()
        switch outcome {
        case .success: return DeliveryResult(externalID: "external-\(sendCount)")
        case .transient: throw ProviderFailure.transient("temporary", retryAfter: nil)
        }
    }
}

private struct TestProvider: Provider {
    let id: String
    let recorder: ProviderRecorder
    let characterLimit = 300

    func send(_ post: PreparedPost, connection: ProviderConnection?) async throws -> DeliveryResult {
        try await recorder.send(post)
    }

    func checkConnection(_ connection: ProviderConnection?) async throws {}
}
