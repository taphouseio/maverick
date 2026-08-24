import Foundation
import MaverickModels

public struct PostPayload: Codable, Sendable {
    public let url: URL
    public let title: String?
    public let description: String
    public let excerpt: String
    public let tags: [String]
    public let publicationDate: Date
    public let isMicroblog: Bool
    public let siteTitle: String
    public let metadata: BroadcastMetadata?

    public init(
        url: URL,
        title: String?,
        description: String,
        excerpt: String,
        tags: [String],
        publicationDate: Date,
        isMicroblog: Bool,
        siteTitle: String,
        metadata: BroadcastMetadata? = nil
    ) {
        self.url = url
        self.title = title
        self.description = description
        self.excerpt = excerpt
        self.tags = tags
        self.publicationDate = publicationDate
        self.isMicroblog = isMicroblog
        self.siteTitle = siteTitle
        self.metadata = metadata
    }

    public var identifier: String { url.absoluteString }
    public var isSupported: Bool { !isMicroblog }
    public var sourceClassification: SourceClassification { isMicroblog ? .microblog : .longForm }
}

public enum SourceClassification: String, Codable, Equatable, Sendable {
    case longForm
    case microblog
}

public struct PreparedPost: Sendable {
    public let source: PostPayload
    public let text: String
    public let renderedTextHash: String
    public let idempotencyKey: String
    public let generation: UInt64

    public init(
        source: PostPayload,
        text: String,
        renderedTextHash: String,
        idempotencyKey: String,
        generation: UInt64 = 0
    ) {
        self.source = source
        self.text = text
        self.renderedTextHash = renderedTextHash
        self.idempotencyKey = idempotencyKey
        self.generation = generation
    }
}

public struct DeliveryResult: Codable, Equatable, Sendable {
    public let externalID: String
    public let externalURL: URL?

    public init(externalID: String, externalURL: URL? = nil) {
        self.externalID = externalID
        self.externalURL = externalURL
    }
}

public struct ProviderConnection: Codable, Equatable, Sendable {
    public let accessToken: String
    public let memberURN: String?
    public let expiresAt: Date?

    public init(accessToken: String, memberURN: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.memberURN = memberURN
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool { expiresAt.map { $0 <= Date() } ?? false }
}

public enum ProviderFailure: Error, Sendable {
    case configuration(String)
    case authentication(String)
    case validation(String)
    case transient(String, retryAfter: TimeInterval?)
    case ambiguous(String)
    case permanent(String)
}

extension ProviderFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .configuration(let message), .authentication(let message), .validation(let message),
             .ambiguous(let message), .permanent(let message):
            return message
        case .transient(let message, _):
            return message
        }
    }
}

public protocol Provider: Sendable {
    var id: String { get }
    var characterLimit: Int { get async throws }
    func send(_ post: PreparedPost, connection: ProviderConnection?) async throws -> DeliveryResult
    func checkConnection(_ connection: ProviderConnection?) async throws
}

public enum DeliveryStatus: String, Codable, CaseIterable, Sendable {
    case observed
    case queued
    case sending
    case delivered
    case skipped
    case failed
    case ambiguous
}

public struct DeliveryState: Codable, Equatable, Sendable {
    public var status: DeliveryStatus
    public var attemptCount: Int
    public var generation: UInt64
    public var renderedTextHash: String?
    public var externalID: String?
    public var externalURL: URL?
    public var lastError: String?
    public var retryAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(status: DeliveryStatus, now: Date = Date()) {
        self.status = status
        self.attemptCount = 0
        self.generation = 0
        self.createdAt = now
        self.updatedAt = now
    }

    private enum CodingKeys: String, CodingKey {
        case status, attemptCount, generation, renderedTextHash, externalID, externalURL
        case lastError, retryAt, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(DeliveryStatus.self, forKey: .status)
        attemptCount = try container.decode(Int.self, forKey: .attemptCount)
        generation = try container.decodeIfPresent(UInt64.self, forKey: .generation) ?? 0
        renderedTextHash = try container.decodeIfPresent(String.self, forKey: .renderedTextHash)
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        externalURL = try container.decodeIfPresent(URL.self, forKey: .externalURL)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        retryAt = try container.decodeIfPresent(Date.self, forKey: .retryAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public struct PostState: Codable, Equatable, Sendable {
    public let url: URL
    public let firstSeenAt: Date
    public let publicationDate: Date
    public let sourceClassification: SourceClassification
    public var deliveries: [String: DeliveryState]

    public init(post: PostPayload, firstSeenAt: Date, deliveries: [String: DeliveryState]) {
        self.url = post.url
        self.firstSeenAt = firstSeenAt
        self.publicationDate = post.publicationDate
        self.sourceClassification = post.sourceClassification
        self.deliveries = deliveries
    }
}

public struct OAuthRequestState: Codable, Equatable, Sendable {
    public let value: String
    public let providerID: String
    public let expiresAt: Date
}

public struct Ledger: Codable, Equatable, Sendable {
    public var revision: UInt64
    public var initializedAt: Date
    public var posts: [String: PostState]
    public var connections: [String: ProviderConnection]
    public var oauthRequests: [String: OAuthRequestState]

    public init(
        revision: UInt64 = 0,
        initializedAt: Date = Date(),
        posts: [String: PostState] = [:],
        connections: [String: ProviderConnection] = [:],
        oauthRequests: [String: OAuthRequestState] = [:]
    ) {
        self.revision = revision
        self.initializedAt = initializedAt
        self.posts = posts
        self.connections = connections
        self.oauthRequests = oauthRequests
    }
}

public struct SnapshotDescriptor: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let key: String
    public let checksum: String
    public let createdAt: Date

    public init(revision: UInt64, key: String, checksum: String, createdAt: Date) {
        self.revision = revision
        self.key = key
        self.checksum = checksum
        self.createdAt = createdAt
    }
}

public enum StoreLoadResult: Sendable {
    case uninitialized
    case loaded(Ledger, SnapshotDescriptor)
}

public protocol StateStore: Sendable {
    func load() async throws -> StoreLoadResult
    func commit(_ ledger: Ledger) async throws -> SnapshotDescriptor
    func snapshots() async throws -> [SnapshotDescriptor]
    func restore(_ snapshot: SnapshotDescriptor) async throws -> Ledger
}

public protocol SecretResolver: Sendable {
    func resolve(_ reference: String) throws -> String
}

public struct FileSecretResolver: SecretResolver {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let path = ProcessInfo.processInfo.environment["MAVERICK_SECRETS_DIRECTORY"], !path.isEmpty {
            self.directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            self.directory = URL(fileURLWithPath: "/run/secrets", isDirectory: true)
        }
    }

    public func resolve(_ reference: String) throws -> String {
        guard reference.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw ProviderFailure.configuration("Invalid secret reference: \(reference)")
        }
        let url = directory.appendingPathComponent(reference, isDirectory: false)
        if let value = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        throw ProviderFailure.configuration("Missing secret: \(reference)")
    }
}

public struct CoordinatorStatus: Sendable {
    public enum Health: Sendable {
        case disabled
        case uninitialized
        case ready
        case unavailable(String)
    }

    public let health: Health
    public let revision: UInt64?
    public let postCount: Int
    public let latestSnapshot: SnapshotDescriptor?
}
