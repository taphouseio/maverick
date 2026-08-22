import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MaverickModels

public protocol ProviderFactory: Sendable {
    var providerType: BroadcastingProviderType { get }
    func make(
        configuration: BroadcastingProviderConfig,
        secrets: any SecretResolver
    ) throws -> any Provider
}

public struct ProviderRegistry: Sendable {
    private let factories: [BroadcastingProviderType: any ProviderFactory]

    public init(factories: [any ProviderFactory] = [
        BlueskyProviderFactory(), MastodonProviderFactory(), LinkedInProviderFactory(),
    ]) {
        self.factories = Dictionary(uniqueKeysWithValues: factories.map { ($0.providerType, $0) })
    }

    public func make(
        configuration: BroadcastingProviderConfig,
        secrets: any SecretResolver
    ) throws -> any Provider {
        guard let factory = factories[configuration.type] else {
            throw ProviderFailure.configuration("No factory is registered for \(configuration.type.rawValue)")
        }
        return try factory.make(configuration: configuration, secrets: secrets)
    }
}

public struct BlueskyProviderFactory: ProviderFactory {
    public let providerType = BroadcastingProviderType.bluesky
    public init() {}
    public func make(configuration: BroadcastingProviderConfig, secrets: any SecretResolver) throws -> any Provider {
        try BlueskyProvider(configuration: configuration, secrets: secrets)
    }
}

public struct MastodonProviderFactory: ProviderFactory {
    public let providerType = BroadcastingProviderType.mastodon
    public init() {}
    public func make(configuration: BroadcastingProviderConfig, secrets: any SecretResolver) throws -> any Provider {
        try MastodonProvider(configuration: configuration, secrets: secrets)
    }
}

public struct LinkedInProviderFactory: ProviderFactory {
    public let providerType = BroadcastingProviderType.linkedin
    public init() {}
    public func make(configuration: BroadcastingProviderConfig, secrets: any SecretResolver) throws -> any Provider {
        LinkedInProvider(configuration: configuration)
    }
}

public struct UnavailableProvider: Provider {
    public let id: String
    public let characterLimit: Int
    private let reason: String

    public init(id: String, characterLimit: Int, reason: String) {
        self.id = id
        self.characterLimit = characterLimit
        self.reason = reason
    }

    public func send(_ post: PreparedPost, connection: ProviderConnection?) async throws -> DeliveryResult {
        throw ProviderFailure.configuration(reason)
    }

    public func checkConnection(_ connection: ProviderConnection?) async throws {
        throw ProviderFailure.configuration(reason)
    }
}

public struct BlueskyProvider: Provider {
    public let id: String
    public let characterLimit = 300

    private let account: String
    private let appPassword: String
    private let serviceURL: URL
    private let linkPreview: Bool

    public init(configuration: BroadcastingProviderConfig, secrets: any SecretResolver) throws {
        guard let account = configuration.account else {
            throw ProviderFailure.configuration("Bluesky provider requires account")
        }
        guard let reference = configuration.credentialSecret else {
            throw ProviderFailure.configuration("Bluesky provider requires credentialSecret")
        }
        self.id = configuration.id
        self.account = account
        self.appPassword = try secrets.resolve(reference)
        self.serviceURL = configuration.serviceURL ?? URL(string: "https://bsky.social")!
        self.linkPreview = configuration.linkPreview
    }

    public func checkConnection(_ connection: ProviderConnection?) async throws {
        _ = try await session()
    }

    public func send(_ post: PreparedPost, connection: ProviderConnection?) async throws -> DeliveryResult {
        let session = try await session()
        let pds = session.pdsURL ?? serviceURL
        let rkey = String(Self.sha256(post.source.identifier).prefix(24))
        let record = Record(
            type: "app.bsky.feed.post",
            text: post.text,
            createdAt: Self.iso8601(Date()),
            facets: Self.urlFacets(in: post.text, url: post.source.url),
            embed: linkPreview ? Embed(
                type: "app.bsky.embed.external",
                external: .init(
                    uri: post.source.url.absoluteString,
                    title: post.source.title ?? post.source.siteTitle,
                    description: post.source.description
                )
            ) : nil
        )
        let body = PutRecordRequest(
            repo: session.did,
            collection: "app.bsky.feed.post",
            rkey: rkey,
            validate: true,
            record: record
        )
        let url = pds.appendingPathComponent("xrpc/com.atproto.repo.putRecord")
        let response = try await HTTP.sendJSON(url: url, method: "POST", bearerToken: session.accessJwt, body: body)
        guard (200..<300).contains(response.statusCode) else {
            throw HTTP.providerFailure(response, operation: "Bluesky post")
        }
        let decoded = try JSONDecoder().decode(PutRecordResponse.self, from: response.data)
        return DeliveryResult(
            externalID: decoded.uri,
            externalURL: URL(string: "https://bsky.app/profile/\(session.did)/post/\(rkey)")
        )
    }

    private func session() async throws -> SessionResponse {
        let body = SessionRequest(identifier: account, password: appPassword)
        let url = serviceURL.appendingPathComponent("xrpc/com.atproto.server.createSession")
        let response = try await HTTP.sendJSON(url: url, method: "POST", body: body)
        guard (200..<300).contains(response.statusCode) else {
            throw HTTP.providerFailure(response, operation: "Bluesky authentication")
        }
        return try JSONDecoder().decode(SessionResponse.self, from: response.data)
    }

    private struct SessionRequest: Encodable { let identifier: String; let password: String }
    private struct SessionResponse: Decodable {
        struct DIDDocument: Decodable {
            struct Service: Decodable { let type: String; let serviceEndpoint: URL }
            let service: [Service]?
        }
        let accessJwt: String
        let did: String
        let didDoc: DIDDocument?

        var pdsURL: URL? {
            didDoc?.service?.first(where: { $0.type == "AtprotoPersonalDataServer" })?.serviceEndpoint
        }
    }
    private struct PutRecordRequest: Encodable {
        let repo: String; let collection: String; let rkey: String; let validate: Bool; let record: Record
    }
    private struct PutRecordResponse: Decodable { let uri: String }
    private struct Record: Encodable {
        let type: String
        let text: String
        let createdAt: String
        let facets: [Facet]
        let embed: Embed?
        enum CodingKeys: String, CodingKey { case type = "$type", text, createdAt, facets, embed }
    }
    private struct Facet: Encodable {
        struct Index: Encodable { let byteStart: Int; let byteEnd: Int }
        struct Feature: Encodable {
            let type = "app.bsky.richtext.facet#link"
            let uri: String
            enum CodingKeys: String, CodingKey { case type = "$type", uri }
        }
        let index: Index
        let features: [Feature]
    }
    private struct Embed: Encodable {
        struct External: Encodable { let uri: String; let title: String; let description: String }
        let type: String
        let external: External
        enum CodingKeys: String, CodingKey { case type = "$type", external }
    }

    private static func urlFacets(in text: String, url: URL) -> [Facet] {
        let value = url.absoluteString
        guard let range = text.range(of: value) else { return [] }
        let byteStart = text[..<range.lowerBound].utf8.count
        let byteEnd = byteStart + value.utf8.count
        return [Facet(index: .init(byteStart: byteStart, byteEnd: byteEnd), features: [.init(uri: value)])]
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

public struct MastodonProvider: Provider {
    public let id: String

    private let instanceURL: URL
    private let accessToken: String
    private let visibility: String

    public init(configuration: BroadcastingProviderConfig, secrets: any SecretResolver) throws {
        guard let instanceURL = configuration.instanceURL else {
            throw ProviderFailure.configuration("Mastodon provider requires instanceURL")
        }
        guard let reference = configuration.accessTokenSecret else {
            throw ProviderFailure.configuration("Mastodon provider requires accessTokenSecret")
        }
        self.id = configuration.id
        self.instanceURL = instanceURL
        self.accessToken = try secrets.resolve(reference)
        self.visibility = configuration.visibility ?? "public"
    }

    public var characterLimit: Int {
        get async throws {
            let url = instanceURL.appendingPathComponent("api/v2/instance")
            let response = try await HTTP.send(url: url, method: "GET")
            guard (200..<300).contains(response.statusCode) else { return 500 }
            return (try? JSONDecoder().decode(Instance.self, from: response.data))?
                .configuration.statuses.maxCharacters ?? 500
        }
    }

    public func checkConnection(_ connection: ProviderConnection?) async throws {
        let url = instanceURL.appendingPathComponent("api/v1/accounts/verify_credentials")
        let response = try await HTTP.send(url: url, method: "GET", bearerToken: accessToken)
        guard (200..<300).contains(response.statusCode) else {
            throw HTTP.providerFailure(response, operation: "Mastodon authentication")
        }
    }

    public func send(_ post: PreparedPost, connection: ProviderConnection?) async throws -> DeliveryResult {
        let url = instanceURL.appendingPathComponent("api/v1/statuses")
        let body = StatusRequest(status: post.text, visibility: visibility)
        let response = try await HTTP.sendJSON(
            url: url,
            method: "POST",
            bearerToken: accessToken,
            headers: ["Idempotency-Key": post.idempotencyKey],
            body: body
        )
        guard (200..<300).contains(response.statusCode) else {
            throw HTTP.providerFailure(response, operation: "Mastodon post")
        }
        let status = try JSONDecoder().decode(StatusResponse.self, from: response.data)
        return DeliveryResult(externalID: status.id, externalURL: status.url)
    }

    private struct Instance: Decodable {
        struct Configuration: Decodable {
            struct Statuses: Decodable {
                let maxCharacters: Int
                enum CodingKeys: String, CodingKey { case maxCharacters = "max_characters" }
            }
            let statuses: Statuses
        }
        let configuration: Configuration
    }
    private struct StatusRequest: Encodable { let status: String; let visibility: String }
    private struct StatusResponse: Decodable { let id: String; let url: URL? }
}

public struct LinkedInProvider: Provider {
    public let id: String
    public let characterLimit = 3_000

    private let version: String
    private let visibility: String

    public init(configuration: BroadcastingProviderConfig) {
        self.id = configuration.id
        self.version = configuration.linkedinVersion ?? "202604"
        self.visibility = configuration.visibility?.uppercased() ?? "PUBLIC"
    }

    public func checkConnection(_ connection: ProviderConnection?) async throws {
        let connection = try validConnection(connection)
        let url = URL(string: "https://api.linkedin.com/v2/userinfo")!
        let response = try await HTTP.send(url: url, method: "GET", bearerToken: connection.accessToken)
        guard (200..<300).contains(response.statusCode) else {
            throw HTTP.providerFailure(response, operation: "LinkedIn authentication")
        }
    }

    public func send(_ post: PreparedPost, connection: ProviderConnection?) async throws -> DeliveryResult {
        let connection = try validConnection(connection)
        guard let memberURN = connection.memberURN else {
            throw ProviderFailure.authentication("LinkedIn connection is missing its member URN")
        }
        let body = PostRequest(
            author: memberURN,
            commentary: post.text,
            visibility: visibility,
            distribution: .init(feedDistribution: "MAIN_FEED", targetEntities: [], thirdPartyDistributionChannels: []),
            content: .init(article: .init(
                source: post.source.url.absoluteString,
                title: post.source.title ?? post.source.siteTitle,
                description: post.source.description
            )),
            lifecycleState: "PUBLISHED",
            isReshareDisabledByAuthor: false
        )
        let response = try await HTTP.sendJSON(
            url: URL(string: "https://api.linkedin.com/rest/posts")!,
            method: "POST",
            bearerToken: connection.accessToken,
            headers: [
                "Linkedin-Version": version,
                "X-Restli-Protocol-Version": "2.0.0",
            ],
            body: body
        )
        guard (200..<300).contains(response.statusCode) else {
            throw HTTP.providerFailure(response, operation: "LinkedIn post")
        }
        guard let externalID = response.headers["x-restli-id"] else {
            throw ProviderFailure.permanent("LinkedIn did not return a post identifier")
        }
        return DeliveryResult(externalID: externalID)
    }

    private func validConnection(_ connection: ProviderConnection?) throws -> ProviderConnection {
        guard let connection else {
            throw ProviderFailure.authentication("LinkedIn is not connected")
        }
        guard !connection.isExpired else {
            throw ProviderFailure.authentication("LinkedIn access token has expired; reconnect in admin")
        }
        return connection
    }

    private struct PostRequest: Encodable {
        struct Distribution: Encodable {
            let feedDistribution: String
            let targetEntities: [String]
            let thirdPartyDistributionChannels: [String]
        }
        struct Content: Encodable {
            struct Article: Encodable { let source: String; let title: String; let description: String }
            let article: Article
        }
        let author: String
        let commentary: String
        let visibility: String
        let distribution: Distribution
        let content: Content
        let lifecycleState: String
        let isReshareDisabledByAuthor: Bool
    }
}

public struct LinkedInOAuthClient: Sendable {
    public struct Token: Sendable {
        public let connection: ProviderConnection
    }

    private let clientID: String
    private let clientSecret: String

    public init(configuration: BroadcastingProviderConfig, secrets: any SecretResolver) throws {
        guard let clientIDSecret = configuration.clientIDSecret,
              let clientSecretSecret = configuration.clientSecretSecret else {
            throw ProviderFailure.configuration("LinkedIn requires clientIDSecret and clientSecretSecret")
        }
        self.clientID = try secrets.resolve(clientIDSecret)
        self.clientSecret = try secrets.resolve(clientSecretSecret)
    }

    public func authorizationURL(redirectURI: URL, state: String) -> URL {
        var components = URLComponents(string: "https://www.linkedin.com/oauth/v2/authorization")!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI.absoluteString),
            .init(name: "state", value: state),
            .init(name: "scope", value: "openid profile w_member_social"),
        ]
        return components.url!
    }

    public func exchange(code: String, redirectURI: URL) async throws -> Token {
        let tokenURL = URL(string: "https://www.linkedin.com/oauth/v2/accessToken")!
        let form = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI.absoluteString,
        ]
        let tokenResponse = try await HTTP.sendForm(url: tokenURL, values: form)
        guard (200..<300).contains(tokenResponse.statusCode) else {
            throw HTTP.providerFailure(tokenResponse, operation: "LinkedIn token exchange")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: tokenResponse.data)
        let userResponse = try await HTTP.send(
            url: URL(string: "https://api.linkedin.com/v2/userinfo")!,
            method: "GET",
            bearerToken: token.accessToken
        )
        guard (200..<300).contains(userResponse.statusCode) else {
            throw HTTP.providerFailure(userResponse, operation: "LinkedIn profile")
        }
        let user = try JSONDecoder().decode(UserInfo.self, from: userResponse.data)
        return Token(connection: ProviderConnection(
            accessToken: token.accessToken,
            memberURN: "urn:li:person:\(user.sub)",
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
        ))
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case expiresIn = "expires_in" }
    }
    private struct UserInfo: Decodable { let sub: String }
}

private enum HTTP {
    struct Response: Sendable {
        let statusCode: Int
        let data: Data
        let headers: [String: String]
    }

    static func sendJSON<Body: Encodable>(
        url: URL,
        method: String,
        bearerToken: String? = nil,
        headers: [String: String] = [:],
        body: Body
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        return try await send(
            url: url,
            method: method,
            bearerToken: bearerToken,
            headers: headers.merging(["Content-Type": "application/json"]) { current, _ in current },
            body: data
        )
    }

    static func sendForm(url: URL, values: [String: String]) async throws -> Response {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = Data((components.percentEncodedQuery ?? "").utf8)
        return try await send(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
    }

    static func send(
        url: URL,
        method: String,
        bearerToken: String? = nil,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, rawResponse) = try await URLSession.shared.data(for: request)
            guard let response = rawResponse as? HTTPURLResponse else {
                throw ProviderFailure.ambiguous("Provider returned a non-HTTP response")
            }
            var resultHeaders: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                resultHeaders[String(describing: key).lowercased()] = String(describing: value)
            }
            return Response(statusCode: response.statusCode, data: data, headers: resultHeaders)
        } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
            throw ProviderFailure.ambiguous("Request outcome is unknown: \(error.localizedDescription)")
        } catch let error as ProviderFailure {
            throw error
        } catch {
            throw ProviderFailure.transient(error.localizedDescription, retryAfter: nil)
        }
    }

    static func providerFailure(_ response: Response, operation: String) -> ProviderFailure {
        let body = String(data: response.data, encoding: .utf8) ?? ""
        let message = "\(operation) returned HTTP \(response.statusCode)\(body.isEmpty ? "" : ": \(body.prefix(500))")"
        switch response.statusCode {
        case 401, 403:
            return .authentication(message)
        case 408, 429:
            return .transient(message, retryAfter: retryAfter(response.headers["retry-after"]))
        case 500...599:
            return .transient(message, retryAfter: nil)
        case 400, 409, 422:
            return .validation(message)
        default:
            return .permanent(message)
        }
    }

    private static func retryAfter(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        return TimeInterval(value)
    }
}
