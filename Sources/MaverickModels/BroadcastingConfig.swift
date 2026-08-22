import Foundation

public struct BroadcastingConfig: Codable, Sendable {
    public let enabled: Bool
    public let autoPublishAfter: Date
    public let state: BroadcastingStateConfig
    public let admin: BroadcastingAdminConfig
    public let providers: [BroadcastingProviderConfig]

    public init(
        enabled: Bool,
        autoPublishAfter: Date,
        state: BroadcastingStateConfig,
        admin: BroadcastingAdminConfig,
        providers: [BroadcastingProviderConfig]
    ) {
        self.enabled = enabled
        self.autoPublishAfter = autoPublishAfter
        self.state = state
        self.admin = admin
        self.providers = providers
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, autoPublishAfter, state, admin, providers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let dateString = try container.decode(String.self, forKey: .autoPublishAfter)
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .autoPublishAfter,
                in: container,
                debugDescription: "autoPublishAfter must be an ISO-8601 timestamp"
            )
        }
        autoPublishAfter = date
        state = try container.decode(BroadcastingStateConfig.self, forKey: .state)
        admin = try container.decode(BroadcastingAdminConfig.self, forKey: .admin)
        providers = try container.decode([BroadcastingProviderConfig].self, forKey: .providers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(ISO8601DateFormatter().string(from: autoPublishAfter), forKey: .autoPublishAfter)
        try container.encode(state, forKey: .state)
        try container.encode(admin, forKey: .admin)
        try container.encode(providers, forKey: .providers)
    }
}

public struct BroadcastingStateConfig: Codable, Sendable {
    public let type: String
    public let bucket: String
    public let keyPrefix: String
    public let accountIDSecret: String
    public let accessKeyIDSecret: String
    public let secretAccessKeySecret: String
    public let encryptionKeySecret: String
    public let localCachePath: String?

    public init(
        type: String = "r2",
        bucket: String,
        keyPrefix: String,
        accountIDSecret: String,
        accessKeyIDSecret: String,
        secretAccessKeySecret: String,
        encryptionKeySecret: String,
        localCachePath: String? = nil
    ) {
        self.type = type
        self.bucket = bucket
        self.keyPrefix = keyPrefix
        self.accountIDSecret = accountIDSecret
        self.accessKeyIDSecret = accessKeyIDSecret
        self.secretAccessKeySecret = secretAccessKeySecret
        self.encryptionKeySecret = encryptionKeySecret
        self.localCachePath = localCachePath
    }

    private enum CodingKeys: String, CodingKey {
        case type, bucket, keyPrefix, accountIDSecret, accessKeyIDSecret
        case secretAccessKeySecret, encryptionKeySecret, localCachePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "r2"
        bucket = try container.decode(String.self, forKey: .bucket)
        keyPrefix = try container.decode(String.self, forKey: .keyPrefix)
        accountIDSecret = try container.decode(String.self, forKey: .accountIDSecret)
        accessKeyIDSecret = try container.decode(String.self, forKey: .accessKeyIDSecret)
        secretAccessKeySecret = try container.decode(String.self, forKey: .secretAccessKeySecret)
        encryptionKeySecret = try container.decode(String.self, forKey: .encryptionKeySecret)
        localCachePath = try container.decodeIfPresent(String.self, forKey: .localCachePath)
    }
}

public struct BroadcastingAdminConfig: Codable, Sendable {
    public let usernameSecret: String
    public let passwordSecret: String

    public init(usernameSecret: String, passwordSecret: String) {
        self.usernameSecret = usernameSecret
        self.passwordSecret = passwordSecret
    }
}

public enum BroadcastingProviderType: String, Codable, Sendable {
    case bluesky
    case mastodon
    case linkedin
}

public struct BroadcastingProviderConfig: Codable, Sendable, Identifiable {
    public let id: String
    public let type: BroadcastingProviderType
    public let enabled: Bool
    public let account: String?
    public let serviceURL: URL?
    public let instanceURL: URL?
    public let credentialSecret: String?
    public let accessTokenSecret: String?
    public let clientIDSecret: String?
    public let clientSecretSecret: String?
    public let linkedinVersion: String?
    public let visibility: String?
    public let linkPreview: Bool
    public let postTemplate: String

    public init(
        id: String,
        type: BroadcastingProviderType,
        enabled: Bool = true,
        account: String? = nil,
        serviceURL: URL? = nil,
        instanceURL: URL? = nil,
        credentialSecret: String? = nil,
        accessTokenSecret: String? = nil,
        clientIDSecret: String? = nil,
        clientSecretSecret: String? = nil,
        linkedinVersion: String? = nil,
        visibility: String? = nil,
        linkPreview: Bool = true,
        postTemplate: String
    ) {
        self.id = id
        self.type = type
        self.enabled = enabled
        self.account = account
        self.serviceURL = serviceURL
        self.instanceURL = instanceURL
        self.credentialSecret = credentialSecret
        self.accessTokenSecret = accessTokenSecret
        self.clientIDSecret = clientIDSecret
        self.clientSecretSecret = clientSecretSecret
        self.linkedinVersion = linkedinVersion
        self.visibility = visibility
        self.linkPreview = linkPreview
        self.postTemplate = postTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, enabled, account, serviceURL, instanceURL, credentialSecret
        case accessTokenSecret, clientIDSecret, clientSecretSecret, linkedinVersion
        case visibility, linkPreview, postTemplate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(BroadcastingProviderType.self, forKey: .type)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        account = try container.decodeIfPresent(String.self, forKey: .account)
        serviceURL = try container.decodeIfPresent(URL.self, forKey: .serviceURL)
        instanceURL = try container.decodeIfPresent(URL.self, forKey: .instanceURL)
        credentialSecret = try container.decodeIfPresent(String.self, forKey: .credentialSecret)
        accessTokenSecret = try container.decodeIfPresent(String.self, forKey: .accessTokenSecret)
        clientIDSecret = try container.decodeIfPresent(String.self, forKey: .clientIDSecret)
        clientSecretSecret = try container.decodeIfPresent(String.self, forKey: .clientSecretSecret)
        linkedinVersion = try container.decodeIfPresent(String.self, forKey: .linkedinVersion)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
        linkPreview = try container.decodeIfPresent(Bool.self, forKey: .linkPreview) ?? true
        postTemplate = try container.decode(String.self, forKey: .postTemplate)
    }
}
