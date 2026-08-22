import Foundation

public struct BroadcastMetadata: Codable, Sendable {
    public let skip: Bool
    public let providers: [String: BroadcastProviderOverride]

    public init(skip: Bool = false, providers: [String: BroadcastProviderOverride] = [:]) {
        self.skip = skip
        self.providers = providers
    }

    private enum CodingKeys: String, CodingKey { case skip, providers }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skip = try container.decodeIfPresent(Bool.self, forKey: .skip) ?? false
        providers = try container.decodeIfPresent([String: BroadcastProviderOverride].self, forKey: .providers) ?? [:]
    }
}

public struct BroadcastProviderOverride: Codable, Sendable {
    public let skip: Bool
    public let template: String?

    public init(skip: Bool = false, template: String? = nil) {
        self.skip = skip
        self.template = template
    }

    private enum CodingKeys: String, CodingKey { case skip, template }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skip = try container.decodeIfPresent(Bool.self, forKey: .skip) ?? false
        template = try container.decodeIfPresent(String.self, forKey: .template)
    }
}
