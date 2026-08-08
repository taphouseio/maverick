import Foundation
import Leaf
import Markdown
import MaverickModels
import Vapor

public enum SupportContentError: Error, Equatable {
    case invalidConfiguration(String)
    case invalidContent(String)
    case invalidAsset(String)
    case notFound(String)
}

public struct SupportContentConfiguration: Sendable {
    public let contentRoot: URL
    public let routePath: [String]
    public let indexTemplate: String
    public let sectionTemplate: String
    public let articleTemplate: String
    public let assetRoute: String
    public let includeDrafts: Bool

    public init(
        contentRoot: URL,
        routePath: [String],
        indexTemplate: String,
        sectionTemplate: String,
        articleTemplate: String,
        assetRoute: String = "_asset",
        includeDrafts: Bool = false
    ) throws {
        let normalizedRoutePath = routePath.filter { !$0.isEmpty }
        guard !normalizedRoutePath.isEmpty,
              normalizedRoutePath.allSatisfy(Self.isSafePathComponent),
              Self.isSafePathComponent(assetRoute),
              !indexTemplate.isEmpty,
              !sectionTemplate.isEmpty,
              !articleTemplate.isEmpty
        else {
            throw SupportContentError.invalidConfiguration("Support route and template configuration is invalid.")
        }

        self.contentRoot = contentRoot.standardizedFileURL
        self.routePath = normalizedRoutePath
        self.indexTemplate = indexTemplate
        self.sectionTemplate = sectionTemplate
        self.articleTemplate = articleTemplate
        self.assetRoute = assetRoute
        self.includeDrafts = includeDrafts
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }
}

public struct SupportLink: Encodable, Equatable, Sendable {
    public let title: String
    public let path: String
    public let url: String

    public init(title: String, path: String, url: String) {
        self.title = title
        self.path = path
        self.url = url
    }
}

public struct SupportNavigationItem: Encodable, Equatable, Sendable {
    public let title: String
    public let path: String
    public let url: String
    public let children: [SupportNavigationItem]
    public let isCurrent: Bool

    public init(title: String, path: String, url: String, children: [SupportNavigationItem], isCurrent: Bool) {
        self.title = title
        self.path = path
        self.url = url
        self.children = children
        self.isCurrent = isCurrent
    }
}

public struct SupportBreadcrumb: Encodable, Equatable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

public struct SupportArticleContext: Encodable, Equatable, Sendable {
    public let path: String
    public let title: String
    public let navTitle: String
    public let description: String?
    public let updatedAt: String?
    public let contentHTML: String
    public let isSection: Bool

    public init(
        path: String,
        title: String,
        navTitle: String,
        description: String?,
        updatedAt: String?,
        contentHTML: String,
        isSection: Bool
    ) {
        self.path = path
        self.title = title
        self.navTitle = navTitle
        self.description = description
        self.updatedAt = updatedAt
        self.contentHTML = contentHTML
        self.isSection = isSection
    }
}

public struct SupportPageContext: Encodable, Equatable, Sendable {
    public let appSlug: String
    public let currentPath: String
    public let pageTitle: String
    public let pageDescription: String?
    public let article: SupportArticleContext
    public let navigation: [SupportNavigationItem]
    public let breadcrumbs: [SupportBreadcrumb]
    public let previous: SupportLink?
    public let next: SupportLink?

    public init(
        appSlug: String,
        currentPath: String,
        pageTitle: String,
        pageDescription: String?,
        article: SupportArticleContext,
        navigation: [SupportNavigationItem],
        breadcrumbs: [SupportBreadcrumb],
        previous: SupportLink?,
        next: SupportLink?
    ) {
        self.appSlug = appSlug
        self.currentPath = currentPath
        self.pageTitle = pageTitle
        self.pageDescription = pageDescription
        self.article = article
        self.navigation = navigation
        self.breadcrumbs = breadcrumbs
        self.previous = previous
        self.next = next
    }
}

public struct SupportRenderTarget: Sendable {
    public let template: String
    public let context: SupportPageContext

    public init(template: String, context: SupportPageContext) {
        self.template = template
        self.context = context
    }
}

public struct SupportAsset: Sendable {
    public let data: Data
    public let mimeType: String
    public let fileName: String

    public init(data: Data, mimeType: String, fileName: String) {
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
    }
}

public actor SupportContentStore {
    private struct ArticleRecord: Sendable {
        let path: String
        let bundle: SupportBundle
        let contentHTML: String
        let isSection: Bool
    }

    private struct Snapshot: Sendable {
        let fingerprint: String
        let articles: [String: ArticleRecord]
    }

    private let configuration: SupportContentConfiguration
    private var snapshot: Snapshot?
    private var failedFingerprint: String?

    public init(configuration: SupportContentConfiguration) {
        self.configuration = configuration
    }

    public func renderTarget(for path: String) throws -> SupportRenderTarget {
        let normalizedPath = try normalizedContentPath(path)
        let snapshot = try currentSnapshot()
        guard let article = snapshot.articles[normalizedPath] else {
            throw SupportContentError.notFound(normalizedPath)
        }

        let page = makePage(for: article, from: snapshot)
        let template: String
        if normalizedPath.isEmpty {
            template = configuration.indexTemplate
        } else if article.isSection {
            template = configuration.sectionTemplate
        } else {
            template = configuration.articleTemplate
        }

        return SupportRenderTarget(template: template, context: page)
    }

    public func asset(bundlePath: String, assetPath: String) throws -> SupportAsset {
        let normalizedBundlePath = try normalizedContentPath(bundlePath)
        let snapshot = try currentSnapshot()
        guard let article = snapshot.articles[normalizedBundlePath] else {
            throw SupportContentError.notFound(normalizedBundlePath)
        }

        let components = try Self.normalizedAssetComponents(assetPath)
        let assetsRoot = article.bundle.assetsURL
        let fileURL = components.reduce(assetsRoot) { $0.appendingPathComponent($1, isDirectory: false) }
        guard isDescendant(fileURL, of: assetsRoot),
              FileManager.default.fileExists(atPath: fileURL.path),
              FileManager.default.fileExists(atPath: fileURL.resolvingSymlinksInPath().path)
        else {
            throw SupportContentError.invalidAsset(assetPath)
        }

        let resolvedURL = fileURL.resolvingSymlinksInPath()
        guard isDescendant(resolvedURL, of: assetsRoot.resolvingSymlinksInPath()) else {
            throw SupportContentError.invalidAsset(assetPath)
        }

        let values = try resolvedURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory != true else {
            throw SupportContentError.invalidAsset(assetPath)
        }

        return SupportAsset(
            data: try Data(contentsOf: resolvedURL),
            mimeType: Self.mimeType(for: resolvedURL.pathExtension),
            fileName: resolvedURL.lastPathComponent
        )
    }

    public func reload() throws {
        let fingerprint = try contentFingerprint()
        let rebuilt = try buildSnapshot(fingerprint: fingerprint)
        snapshot = rebuilt
        failedFingerprint = nil
    }

    private func currentSnapshot() throws -> Snapshot {
        let fingerprint = try contentFingerprint()
        if let snapshot, snapshot.fingerprint == fingerprint {
            return snapshot
        }

        if failedFingerprint != fingerprint, let currentSnapshot = snapshot {
            do {
                let rebuilt = try buildSnapshot(fingerprint: fingerprint)
                self.snapshot = rebuilt
                failedFingerprint = nil
                return rebuilt
            } catch {
                failedFingerprint = fingerprint
                return currentSnapshot
            }
        }

        if let snapshot {
            return snapshot
        }

        let rebuilt = try buildSnapshot(fingerprint: fingerprint)
        snapshot = rebuilt
        failedFingerprint = nil
        return rebuilt
    }

    private func buildSnapshot(fingerprint: String) throws -> Snapshot {
        let root = configuration.contentRoot
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw SupportContentError.invalidContent("Support content root does not exist: (root.path)")
        }

        var records: [String: ArticleRecord] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw SupportContentError.invalidContent("Unable to enumerate support content.")
        }

        while let candidate = enumerator.nextObject() as? URL {
            let values = try candidate.resourceValues(forKeys: Set(keys))
            guard values.isDirectory == true, candidate.pathExtension == "textbundle" else { continue }
            enumerator.skipDescendants()

            guard isDescendant(candidate, of: root),
                  isDescendant(candidate.resolvingSymlinksInPath(), of: root.resolvingSymlinksInPath())
            else {
                throw SupportContentError.invalidContent("Bundle escapes the support content root: (candidate.path)")
            }

            let relativeBundlePath = try relativePath(of: candidate, from: root)
            let contentPath = try contentPath(forBundleRelativePath: relativeBundlePath)
            let bundle = try TextBundleReader.attemptToReadSupportBundle(at: candidate)
            guard !bundle.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SupportContentError.invalidContent("Bundle has an empty title: (candidate.path)")
            }
            if bundle.metadata.draft && !configuration.includeDrafts { continue }
            guard records[contentPath] == nil else {
                throw SupportContentError.invalidContent("Duplicate support content path: (contentPath)")
            }

            let html = try SupportMarkdownRenderer.render(
                bundle.markdown,
                assetURL: { [configuration] source in
                    try Self.assetURL(configuration: configuration, bundlePath: contentPath, source: source)
                }
            )
            records[contentPath] = ArticleRecord(
                path: contentPath,
                bundle: bundle,
                contentHTML: html,
                isSection: !contentPath.isEmpty && relativeBundlePath.hasSuffix("/index.textbundle")
            )
        }

        guard records[""] != nil else {
            throw SupportContentError.invalidContent("Support content requires an index.textbundle at its root.")
        }

        return Snapshot(fingerprint: fingerprint, articles: records)
    }

    private func makePage(for article: ArticleRecord, from snapshot: Snapshot) -> SupportPageContext {
        let navigation = navigationItems(from: snapshot.articles, parent: "", currentPath: article.path)
        let flattened = flatten(navigation)
        let currentIndex = flattened.firstIndex { $0.path == article.path }
        let previous = currentIndex.flatMap { index in index > 0 ? flattened[index - 1] : nil }
        let next = currentIndex.flatMap { index in index + 1 < flattened.count ? flattened[index + 1] : nil }

        let articleContext = SupportArticleContext(
            path: article.path,
            title: article.bundle.metadata.title,
            navTitle: article.bundle.metadata.navTitle ?? article.bundle.metadata.title,
            description: article.bundle.metadata.description,
            updatedAt: article.bundle.metadata.updatedAt.map(Self.dateString),
            contentHTML: article.contentHTML,
            isSection: article.isSection
        )

        return SupportPageContext(
            appSlug: configuration.routePath.first ?? "support",
            currentPath: article.path,
            pageTitle: article.bundle.metadata.title,
            pageDescription: article.bundle.metadata.description,
            article: articleContext,
            navigation: navigation,
            breadcrumbs: breadcrumbs(for: article, from: snapshot.articles),
            previous: previous,
            next: next
        )
    }

    private func navigationItems(
        from records: [String: ArticleRecord],
        parent: String,
        currentPath: String
    ) -> [SupportNavigationItem] {
        records.values
            .filter { $0.path != "" && directParent(of: $0.path) == parent }
            .sorted(by: sortRecords)
            .map { record in
                SupportNavigationItem(
                    title: record.bundle.metadata.navTitle ?? record.bundle.metadata.title,
                    path: record.path,
                    url: contentURL(for: record.path),
                    children: navigationItems(from: records, parent: record.path, currentPath: currentPath),
                    isCurrent: record.path == currentPath
                )
            }
    }

    private func flatten(_ items: [SupportNavigationItem]) -> [SupportLink] {
        items.flatMap { item in
            [SupportLink(title: item.title, path: item.path, url: item.url)] + flatten(item.children)
        }
    }

    private func breadcrumbs(for article: ArticleRecord, from records: [String: ArticleRecord]) -> [SupportBreadcrumb] {
        var result = [SupportBreadcrumb(title: "Help", url: contentURL(for: ""))]
        guard !article.path.isEmpty else { return result }

        let components = article.path.split(separator: "/").map(String.init)
        for index in components.indices {
            let path = components[0...index].joined(separator: "/")
            let title = records[path]?.bundle.metadata.navTitle ?? records[path]?.bundle.metadata.title ?? components[index]
            result.append(SupportBreadcrumb(title: title, url: contentURL(for: path)))
        }
        return result
    }

    private func sortRecords(_ lhs: ArticleRecord, _ rhs: ArticleRecord) -> Bool {
        let lhsOrder = lhs.bundle.metadata.order
        let rhsOrder = rhs.bundle.metadata.order
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
        let lhsTitle = lhs.bundle.metadata.navTitle ?? lhs.bundle.metadata.title
        let rhsTitle = rhs.bundle.metadata.navTitle ?? rhs.bundle.metadata.title
        if lhsTitle.localizedStandardCompare(rhsTitle) != .orderedSame {
            return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
        }
        return lhs.path < rhs.path
    }

    private func contentURL(for path: String) -> String {
        let components = configuration.routePath + (path.isEmpty ? [] : path.split(separator: "/").map(String.init))
        return "/" + components.map(Self.urlEncodePathComponent).joined(separator: "/")
    }

    private static func assetURL(configuration: SupportContentConfiguration, bundlePath: String, source: String) throws -> String? {
        let decoded = source.removingPercentEncoding ?? source
        let relative: String
        if decoded.hasPrefix("./assets/") {
            relative = String(decoded.dropFirst("./assets/".count))
        } else if decoded.hasPrefix("assets/") {
            relative = String(decoded.dropFirst("assets/".count))
        } else {
            return nil
        }

        _ = try normalizedAssetComponents(relative)
        var components = URLComponents()
        components.path = "/" + (configuration.routePath + [configuration.assetRoute])
            .map(Self.urlEncodePathComponent)
            .joined(separator: "/")
        components.queryItems = [
            URLQueryItem(name: "article", value: bundlePath),
            URLQueryItem(name: "path", value: relative),
        ]
        return components.string
    }

    private func contentFingerprint() throws -> String {
        let root = configuration.contentRoot
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw SupportContentError.invalidContent("Support content root does not exist: (root.path)")
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw SupportContentError.invalidContent("Unable to fingerprint support content.")
        }

        var entries: [String] = []
        while let candidate = enumerator.nextObject() as? URL {
            let values = try candidate.resourceValues(forKeys: Set(keys))
            guard values.isDirectory != nil else { continue }
            entries.append([
                candidate.path,
                values.contentModificationDate?.timeIntervalSince1970.description ?? "",
                values.fileSize.map(String.init) ?? "",
            ].joined(separator: "|"))
        }
        return entries.sorted().joined(separator: "\n")
    }

    private func relativePath(of url: URL, from root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(rootPath) else {
            throw SupportContentError.invalidContent("Bundle is outside the configured content root.")
        }
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }

    private func contentPath(forBundleRelativePath path: String) throws -> String {
        let components = path.split(separator: "/").map(String.init)
        guard let last = components.last, last.hasSuffix(".textbundle") else {
            throw SupportContentError.invalidContent("Invalid textbundle path: (path)")
        }
        var result = components.dropLast().map { $0 }
        let name = String(last.dropLast(".textbundle".count))
        if name != "index" { result.append(name) }
        return try normalizedContentPath(result.joined(separator: "/"))
    }

    private func normalizedContentPath(_ path: String) throws -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("\\") }) else {
            throw SupportContentError.invalidContent("Invalid support content path: (path)")
        }
        return components.joined(separator: "/")
    }

    private static func normalizedAssetComponents(_ path: String) throws -> [String] {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("\\") }) else {
            throw SupportContentError.invalidAsset(path)
        }
        return components
    }

    private func directParent(of path: String) -> String {
        guard let index = path.lastIndex(of: "/") else { return "" }
        return String(path[..<index])
    }

    private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        return candidate.standardizedFileURL.path == root.standardizedFileURL.path || candidate.standardizedFileURL.path.hasPrefix(rootPath)
    }

    private static func urlEncodePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func mimeType(for extension: String) -> String {
        switch `extension`.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "json": return "application/json"
        case "txt", "md": return "text/plain; charset=utf-8"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }
}

private enum SupportMarkdownRenderer {
    static func render(_ markdown: String, assetURL: @escaping (String) throws -> String?) throws -> String {
        var rewriter = AssetLinkRewriter(assetURL: assetURL)
        let document = Document(parsing: markdown)
        guard let rewritten = rewriter.visit(document) else {
            throw SupportContentError.invalidContent("Unable to rewrite support Markdown.")
        }
        if let invalidSource = rewriter.invalidSource {
            throw SupportContentError.invalidAsset(invalidSource)
        }
        return HTMLFormatter.format(rewritten)
    }

    private struct AssetLinkRewriter: MarkupRewriter {
        let assetURL: (String) throws -> String?
        var invalidSource: String?

        mutating func visitImage(_ image: Image) -> Markup? {
            var image = image
            do {
                if let source = image.source, let rewritten = try assetURL(source) {
                    image.source = rewritten
                }
            } catch {
                invalidSource = image.source
            }
            return defaultVisit(image)
        }

        mutating func visitLink(_ link: Link) -> Markup? {
            var link = link
            do {
                if let destination = link.destination, let rewritten = try assetURL(destination) {
                    link.destination = rewritten
                }
            } catch {
                invalidSource = link.destination
            }
            return defaultVisit(link)
        }
    }
}

public struct SupportRouteCollection<Context: Encodable & Sendable>: RouteCollection, Sendable {
    private let configuration: SupportContentConfiguration
    private let store: SupportContentStore
    private let makeContext: @Sendable (SupportPageContext) -> Context

    public init(
        configuration: SupportContentConfiguration,
        store: SupportContentStore? = nil,
        makeContext: @escaping @Sendable (SupportPageContext) -> Context
    ) {
        self.configuration = configuration
        self.store = store ?? SupportContentStore(configuration: configuration)
        self.makeContext = makeContext
    }

    public func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped(configuration.routePath.map(PathComponent.constant))

        group.get { req async throws -> View in
            try await render(path: "", request: req)
        }

        group.get("**") { req async throws -> View in
            let path = req.parameters.getCatchall().joined(separator: "/")
            if path == configuration.assetRoute {
                throw Abort(.notFound)
            }
            return try await render(path: path, request: req)
        }

        group.get(PathComponent.constant(configuration.assetRoute)) { req async throws -> Response in
            guard let bundlePath = try? req.query.get(String.self, at: ["article"]),
                  let assetPath = try? req.query.get(String.self, at: ["path"])
            else {
                throw Abort(.badRequest)
            }

            do {
                let asset = try await store.asset(bundlePath: bundlePath, assetPath: assetPath)
                let response = Response(status: .ok)
                response.headers.replaceOrAdd(name: "Content-Type", value: asset.mimeType)
                response.headers.replaceOrAdd(name: "Content-Disposition", value: "inline; filename=\"\(asset.fileName)\"")
                response.body = .init(data: asset.data)
                return response
            } catch let error as SupportContentError {
                throw error.abort
            }
        }
    }

    private func render(path: String, request: Request) async throws -> View {
        do {
            let target = try await store.renderTarget(for: path)
            return try await request.view.render(target.template, makeContext(target.context)).get()
        } catch let error as SupportContentError {
            throw error.abort
        }
    }
}

private extension SupportContentError {
    var abort: Abort {
        switch self {
        case .notFound: return Abort(.notFound)
        case .invalidAsset: return Abort(.notFound)
        case .invalidConfiguration, .invalidContent: return Abort(.serviceUnavailable)
        }
    }
}
