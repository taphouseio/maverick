import Foundation
import MaverickBroadcast
import MaverickLib
import MaverickModels
import Vapor

final class BroadcastRuntime: Sendable {
    let configuration: BroadcastingConfig
    let coordinator: Coordinator?
    let startupError: String?
    let secrets: FileSecretResolver

    private init(
        configuration: BroadcastingConfig,
        coordinator: Coordinator?,
        startupError: String?,
        secrets: FileSecretResolver
    ) {
        self.configuration = configuration
        self.coordinator = coordinator
        self.startupError = startupError
        self.secrets = secrets
    }

    static func make(configuration: BroadcastingConfig) async -> BroadcastRuntime {
        let secrets = FileSecretResolver()
        do {
            let store = try R2StateStore(configuration: configuration.state, secrets: secrets)
            let registry = ProviderRegistry()
            let providers: [any Provider] = configuration.providers.filter(\.enabled).map { provider in
                do {
                    return try registry.make(configuration: provider, secrets: secrets)
                } catch {
                    let limit: Int
                    switch provider.type {
                    case .bluesky: limit = 300
                    case .mastodon: limit = 500
                    case .linkedin: limit = 3_000
                    }
                    return UnavailableProvider(id: provider.id, characterLimit: limit, reason: error.localizedDescription)
                }
            }
            let coordinator = Coordinator(configuration: configuration, store: store, providers: providers)
            await coordinator.start()
            return BroadcastRuntime(
                configuration: configuration,
                coordinator: coordinator,
                startupError: nil,
                secrets: secrets
            )
        } catch {
            return BroadcastRuntime(
                configuration: configuration,
                coordinator: nil,
                startupError: error.localizedDescription,
                secrets: secrets
            )
        }
    }

    func currentPosts() throws -> [PostPayload] {
        let site = try SiteConfigController.fetchSite()
        return try FeedOutput.allPosts(for: .fullText).compactMap { post in
            guard let url = URL(string: post.url) else { return nil }
            return PostPayload(
                url: url,
                title: post.title,
                description: post.shortDescription ?? "",
                excerpt: Self.plainText(from: post.content, limit: 1_000),
                tags: post.frontMatter.tags,
                publicationDate: post.date,
                isMicroblog: post.frontMatter.isMicroblog,
                siteTitle: site.title,
                metadata: post.broadcastMetadata
            )
        }
    }

    func linkedinOAuthClient(providerID: String) throws -> LinkedInOAuthClient {
        guard let configuration = configuration.providers.first(where: {
            $0.id == providerID && $0.type == .linkedin
        }) else {
            throw ProviderFailure.configuration("LinkedIn provider was not found")
        }
        return try LinkedInOAuthClient(configuration: configuration, secrets: secrets)
    }

    private static func plainText(from html: String, limit: Int) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"<script\b[^>]*>[\s\S]*?</script>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<style\b[^>]*>[\s\S]*?</style>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(limit))
    }
}

private struct BroadcastRuntimeKey: StorageKey {
    typealias Value = BroadcastRuntime
}

extension Application {
    var broadcastRuntime: BroadcastRuntime? {
        get { storage[BroadcastRuntimeKey.self] }
        set { storage[BroadcastRuntimeKey.self] = newValue }
    }
}
