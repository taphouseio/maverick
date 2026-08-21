import Foundation
import JSONValue

public struct BundleContentMetadata: Codable, Equatable, Sendable {
    public let title: String
    public let description: String?
    public let updatedAt: Date?
    public let order: Int
    public let navTitle: String?
    public let draft: Bool
    public let tags: [String]
    public let extensions: [String: JSONValue]

    public init(
        title: String,
        description: String? = nil,
        updatedAt: Date? = nil,
        order: Int = 0,
        navTitle: String? = nil,
        draft: Bool = false,
        tags: [String] = [],
        extensions: [String: JSONValue] = [:]
    ) {
        self.title = title
        self.description = description
        self.updatedAt = updatedAt
        self.order = order
        self.navTitle = navTitle
        self.draft = draft
        self.tags = tags
        self.extensions = extensions
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case updatedAt
        case order
        case navTitle
        case draft
        case tags
        case extensions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.updatedAt = try container.decodeMaverickDateIfPresent(forKey: .updatedAt)
        self.order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        self.navTitle = try container.decodeIfPresent(String.self, forKey: .navTitle)
        self.draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.extensions = try container.decodeIfPresent([String: JSONValue].self, forKey: .extensions) ?? [:]
    }
}

public struct BundleContentBundle: Sendable {
    public let metadata: BundleContentMetadata
    public let markdown: String
    public let bundleURL: URL
    public let assetsURL: URL

    public init(metadata: BundleContentMetadata, markdown: String, bundleURL: URL, assetsURL: URL) {
        self.metadata = metadata
        self.markdown = markdown
        self.bundleURL = bundleURL
        self.assetsURL = assetsURL
    }
}

private extension KeyedDecodingContainer {
    func decodeMaverickDateIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
