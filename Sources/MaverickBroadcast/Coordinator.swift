import Crypto
import Foundation
import MaverickModels

public actor Coordinator {
    private let configuration: BroadcastingConfig
    private let store: any StateStore
    private let renderer: TemplateRenderer
    private let providers: [String: any Provider]
    private let providerConfigurations: [String: BroadcastingProviderConfig]

    private var ledger: Ledger?
    private var latestSnapshot: SnapshotDescriptor?
    private var latestPosts: [String: PostPayload] = [:]
    private var health: CoordinatorStatus.Health
    private var processing = false

    public init(
        configuration: BroadcastingConfig,
        store: any StateStore,
        providers: [any Provider],
        renderer: TemplateRenderer = TemplateRenderer()
    ) {
        self.configuration = configuration
        self.store = store
        self.renderer = renderer
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.providerConfigurations = Dictionary(uniqueKeysWithValues: configuration.providers.map { ($0.id, $0) })
        self.health = .uninitialized
    }

    public func start() async {
        do {
            switch try await store.load() {
            case .uninitialized:
                health = .uninitialized
            case .loaded(var restored, let snapshot):
                var recoveredAmbiguous = false
                for postID in restored.posts.keys {
                    let providerIDs = restored.posts[postID].map { Array($0.deliveries.keys) } ?? []
                    for providerID in providerIDs {
                        guard restored.posts[postID]?.deliveries[providerID]?.status == .sending else { continue }
                        restored.posts[postID]?.deliveries[providerID]?.status = .ambiguous
                        restored.posts[postID]?.deliveries[providerID]?.lastError =
                            "Maverick restarted while this delivery was in progress"
                        restored.posts[postID]?.deliveries[providerID]?.updatedAt = Date()
                        recoveredAmbiguous = true
                    }
                }
                ledger = restored
                latestSnapshot = snapshot
                health = .ready
                if recoveredAmbiguous { try await commit() }
            }
        } catch {
            health = .unavailable(error.localizedDescription)
        }
    }

    public func status() -> CoordinatorStatus {
        CoordinatorStatus(
            health: health,
            revision: ledger?.revision,
            postCount: ledger?.posts.count ?? 0,
            latestSnapshot: latestSnapshot
        )
    }

    public func ledgerSnapshot() -> Ledger? { ledger }

    public func observe(_ posts: [PostPayload]) async {
        latestPosts = Dictionary(uniqueKeysWithValues: posts.map { ($0.identifier, $0) })
        guard ledger != nil, case .ready = health else { return }

        do {
            var changed = false
            let now = Date()
            for post in posts {
                if ledger?.posts[post.identifier] != nil {
                    for providerConfig in configuration.providers
                    where ledger?.posts[post.identifier]?.deliveries[providerConfig.id] == nil {
                        let status: DeliveryStatus = (!post.isSupported || providerConfig.enabled == false) ? .skipped : .observed
                        ledger?.posts[post.identifier]?.deliveries[providerConfig.id] = DeliveryState(status: status, now: now)
                        changed = true
                    }
                    continue
                }
                var deliveries: [String: DeliveryState] = [:]
                for providerConfig in configuration.providers {
                    let status: DeliveryStatus
                    if !providerConfig.enabled || !post.isSupported || post.metadata?.skip == true ||
                        post.metadata?.providers[providerConfig.id]?.skip == true {
                        status = .skipped
                    } else if !configuration.enabled || post.publicationDate < configuration.autoPublishAfter {
                        status = .observed
                    } else {
                        status = .queued
                    }
                    deliveries[providerConfig.id] = DeliveryState(status: status, now: now)
                }
                ledger?.posts[post.identifier] = PostState(post: post, firstSeenAt: now, deliveries: deliveries)
                changed = true
            }
            if changed { try await commit() }
            if configuration.enabled { try await processDueDeliveries() }
        } catch {
            health = .unavailable(error.localizedDescription)
        }
    }

    public func initialize(with posts: [PostPayload]) async throws {
        guard ledger == nil else { return }
        guard case .uninitialized = health else {
            throw R2StoreError.unavailable("Refusing to create a new ledger while authoritative R2 state is unavailable")
        }
        let now = Date()
        var initialized = Ledger(initializedAt: now)
        for post in posts {
            let deliveries = Dictionary(uniqueKeysWithValues: configuration.providers.map { provider in
                let status: DeliveryStatus = post.isSupported ? .observed : .skipped
                return (provider.id, DeliveryState(status: status, now: now))
            })
            initialized.posts[post.identifier] = PostState(post: post, firstSeenAt: now, deliveries: deliveries)
        }
        ledger = initialized
        latestPosts = Dictionary(uniqueKeysWithValues: posts.map { ($0.identifier, $0) })
        do {
            try await commit()
            health = .ready
        } catch {
            ledger = nil
            health = .unavailable(error.localizedDescription)
            throw error
        }
    }

    public func preview(postID: String, providerID: String) async throws -> String {
        guard let post = latestPosts[postID] else {
            throw ProviderFailure.validation("Post is not available in the current content tree")
        }
        guard post.isSupported else {
            throw ProviderFailure.validation("Micropost broadcasting is deferred in v1")
        }
        guard let provider = providers[providerID], let config = providerConfigurations[providerID] else {
            throw ProviderFailure.configuration("Unknown provider: \(providerID)")
        }
        return try renderer.render(post: post, provider: config, characterLimit: await provider.characterLimit)
    }

    public func backfill(postID: String, providerIDs: [String]) async throws {
        try requireReady()
        guard latestPosts[postID]?.isSupported == true else {
            throw ProviderFailure.validation("Only supported long-form posts can be backfilled")
        }
        guard ledger?.posts[postID] != nil else {
            throw ProviderFailure.validation("Post has not been observed")
        }
        for providerID in providerIDs {
            guard var delivery = ledger?.posts[postID]?.deliveries[providerID] else { continue }
            guard delivery.status != .delivered && delivery.status != .sending else { continue }
            delivery.status = .queued
            delivery.lastError = nil
            delivery.retryAt = nil
            delivery.updatedAt = Date()
            ledger?.posts[postID]?.deliveries[providerID] = delivery
        }
        try await commit()
        try await processDueDeliveries()
    }

    public func retry(postID: String, providerID: String) async throws {
        try requireReady()
        guard var delivery = ledger?.posts[postID]?.deliveries[providerID] else {
            throw ProviderFailure.validation("Delivery was not found")
        }
        guard delivery.status == .failed else {
            throw ProviderFailure.validation("Only failed deliveries can be retried automatically")
        }
        delivery.status = .queued
        delivery.retryAt = nil
        delivery.lastError = nil
        delivery.updatedAt = Date()
        ledger?.posts[postID]?.deliveries[providerID] = delivery
        try await commit()
        try await processDueDeliveries()
    }

    public func explicitlyQueue(postID: String, providerID: String) async throws {
        try requireReady()
        guard latestPosts[postID]?.isSupported == true,
              var delivery = ledger?.posts[postID]?.deliveries[providerID] else {
            throw ProviderFailure.validation("Delivery or source post was not found")
        }
        guard delivery.status != .sending else {
            throw ProviderFailure.validation("A sending delivery cannot be queued again")
        }
        if delivery.status == .delivered {
            delivery.generation += 1
        }
        delivery.status = .queued
        delivery.externalID = nil
        delivery.externalURL = nil
        delivery.lastError = nil
        delivery.retryAt = nil
        delivery.updatedAt = Date()
        ledger?.posts[postID]?.deliveries[providerID] = delivery
        try await commit()
        try await processDueDeliveries()
    }

    public func checkConnection(providerID: String) async throws {
        guard let provider = providers[providerID] else {
            throw ProviderFailure.configuration("Unknown provider: \(providerID)")
        }
        try await provider.checkConnection(ledger?.connections[providerID])
    }

    public func connection(providerID: String) -> ProviderConnection? {
        ledger?.connections[providerID]
    }

    public func beginOAuth(providerID: String) async throws -> String {
        try requireReady()
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        ledger?.oauthRequests[value] = OAuthRequestState(
            value: value,
            providerID: providerID,
            expiresAt: Date().addingTimeInterval(600)
        )
        try await commit()
        return value
    }

    public func consumeOAuthState(_ state: String) async throws -> String {
        try requireReady()
        guard let request = ledger?.oauthRequests.removeValue(forKey: state), request.expiresAt > Date() else {
            throw ProviderFailure.authentication("OAuth state is invalid or expired")
        }
        try await commit()
        return request.providerID
    }

    public func saveConnection(_ connection: ProviderConnection, providerID: String) async throws {
        try requireReady()
        guard providerConfigurations[providerID]?.type == .linkedin else {
            throw ProviderFailure.configuration("Unknown LinkedIn provider: \(providerID)")
        }
        ledger?.connections[providerID] = connection
        try await commit()
    }

    public func availableSnapshots() async throws -> [SnapshotDescriptor] {
        try await store.snapshots()
    }

    public func restore(_ snapshot: SnapshotDescriptor) async throws {
        var restored = try await store.restore(snapshot)
        for postID in restored.posts.keys {
            let providerIDs = restored.posts[postID].map { Array($0.deliveries.keys) } ?? []
            for providerID in providerIDs where restored.posts[postID]?.deliveries[providerID]?.status == .sending {
                restored.posts[postID]?.deliveries[providerID]?.status = .ambiguous
                restored.posts[postID]?.deliveries[providerID]?.lastError = "Restored snapshot contained an in-progress delivery"
                restored.posts[postID]?.deliveries[providerID]?.updatedAt = Date()
            }
        }
        ledger = restored
        latestSnapshot = snapshot
        health = .ready
        // Restoring is itself a new authoritative commit, preserving monotonic revision order.
        let highest = try await store.snapshots().map(\.revision).max() ?? restored.revision
        ledger?.revision = max(highest, restored.revision)
        try await commit()
    }

    private func processDueDeliveries() async throws {
        guard !processing, case .ready = health else { return }
        processing = true
        defer { processing = false }

        let now = Date()
        let candidates = ledger?.posts.flatMap { postID, state in
            state.deliveries.compactMap { providerID, delivery -> (String, String)? in
                switch delivery.status {
                case .queued:
                    return (postID, providerID)
                case .failed where delivery.retryAt.map({ $0 <= now }) == true:
                    return (postID, providerID)
                default:
                    return nil
                }
            }
        } ?? []

        for (postID, providerID) in candidates {
            try Task.checkCancellation()
            guard let post = latestPosts[postID],
                  let provider = providers[providerID],
                  let config = providerConfigurations[providerID],
                  config.enabled else { continue }
            try await deliver(post: post, provider: provider, configuration: config)
        }
    }

    private func deliver(
        post: PostPayload,
        provider: any Provider,
        configuration: BroadcastingProviderConfig
    ) async throws {
        guard var delivery = ledger?.posts[post.identifier]?.deliveries[provider.id] else { return }
        do {
            let text = try renderer.render(
                post: post,
                provider: configuration,
                characterLimit: await provider.characterLimit
            )
            let textHash = renderer.hash(text)
            delivery.status = .sending
            delivery.attemptCount += 1
            delivery.renderedTextHash = textHash
            delivery.lastError = nil
            delivery.retryAt = nil
            delivery.updatedAt = Date()
            ledger?.posts[post.identifier]?.deliveries[provider.id] = delivery
            try await commit()

            let idempotencyKey = Self.idempotencyKey(
                postID: post.identifier,
                providerID: provider.id,
                generation: delivery.generation
            )
            let prepared = PreparedPost(
                source: post,
                text: text,
                renderedTextHash: textHash,
                idempotencyKey: idempotencyKey
            )
            let result = try await provider.send(prepared, connection: ledger?.connections[provider.id])
            delivery.status = .delivered
            delivery.externalID = result.externalID
            delivery.externalURL = result.externalURL
            delivery.lastError = nil
            delivery.retryAt = nil
            delivery.updatedAt = Date()
        } catch let failure as ProviderFailure {
            apply(failure, to: &delivery)
        } catch {
            delivery.status = .failed
            delivery.lastError = error.localizedDescription
            delivery.retryAt = retryDate(attempt: delivery.attemptCount, explicit: nil)
            delivery.updatedAt = Date()
        }
        ledger?.posts[post.identifier]?.deliveries[provider.id] = delivery
        try await commit()
    }

    private func apply(_ failure: ProviderFailure, to delivery: inout DeliveryState) {
        delivery.lastError = failure.localizedDescription
        delivery.updatedAt = Date()
        switch failure {
        case .ambiguous:
            delivery.status = .ambiguous
            delivery.retryAt = nil
        case .transient(_, let retryAfter):
            delivery.status = .failed
            delivery.retryAt = retryDate(attempt: delivery.attemptCount, explicit: retryAfter)
        case .authentication, .configuration, .validation, .permanent:
            delivery.status = .failed
            delivery.retryAt = nil
        }
    }

    private func retryDate(attempt: Int, explicit: TimeInterval?) -> Date {
        let schedule: [TimeInterval] = [60, 300, 1_800, 7_200, 43_200, 86_400]
        let delay = explicit ?? schedule[min(max(attempt - 1, 0), schedule.count - 1)]
        return Date().addingTimeInterval(delay)
    }

    private func commit() async throws {
        guard var pending = ledger else { throw R2StoreError.invalidSnapshot("No ledger to commit") }
        let previous = ledger
        pending.revision += 1
        ledger = pending
        do {
            latestSnapshot = try await store.commit(pending)
        } catch {
            ledger = previous
            health = .unavailable(error.localizedDescription)
            throw error
        }
    }

    private func requireReady() throws {
        guard case .ready = health, ledger != nil else {
            throw R2StoreError.unavailable("Broadcasting is not ready because authoritative R2 state is unavailable")
        }
    }

    private static func idempotencyKey(postID: String, providerID: String, generation: UInt64) -> String {
        let data = Data("\(providerID):\(postID):\(generation)".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
