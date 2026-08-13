import Foundation
import Leaf
import MaverickModels
import Vapor

public struct BundleContentLink: Encodable, Equatable, Sendable {
    public let title: String
    public let path: String
    public let url: String

    public init(title: String, path: String, url: String) {
        self.title = title
        self.path = path
        self.url = url
    }
}

public struct BundleContentNavigationItem: Encodable, Equatable, Sendable {
    public let title: String
    public let path: String
    public let url: String
    public let children: [BundleContentNavigationItem]
    public let isCurrent: Bool

    public init(title: String, path: String, url: String, children: [BundleContentNavigationItem], isCurrent: Bool) {
        self.title = title
        self.path = path
        self.url = url
        self.children = children
        self.isCurrent = isCurrent
    }
}

public struct BundleContentBreadcrumb: Encodable, Equatable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

public enum BundleContentError: Error, Equatable {
    case invalidConfiguration(String)
    case invalidContent(String)
    case invalidAsset(String)
    case notFound(String)
}

public struct BundleContentConfiguration: Sendable {
    public let contentRoot: URL
    public let bundleURL: URL?
    public let routePath: [String]
    public let pageTemplate: String
    public let indexTemplate: String?
    public let sectionTemplate: String?
    public let articleTemplate: String?
    public let assetRoute: String
    public let includeDrafts: Bool

    public init(
        contentRoot: URL,
        routePath: [String] = [],
        pageTemplate: String,
        assetRoute: String = "_asset",
        includeDrafts: Bool = false,
        bundleURL: URL? = nil,
        indexTemplate: String? = nil,
        sectionTemplate: String? = nil,
        articleTemplate: String? = nil
    ) throws {
        let normalizedRoutePath = routePath.filter { !$0.isEmpty }
        guard normalizedRoutePath.allSatisfy(Self.isSafePathComponent),
              Self.isSafePathComponent(assetRoute),
              !pageTemplate.isEmpty
        else {
            throw BundleContentError.invalidConfiguration("Bundle content route and template configuration is invalid.")
        }

        self.contentRoot = contentRoot.standardizedFileURL
        self.bundleURL = bundleURL?.standardizedFileURL
        self.routePath = normalizedRoutePath
        self.pageTemplate = pageTemplate
        self.indexTemplate = indexTemplate
        self.sectionTemplate = sectionTemplate
        self.articleTemplate = articleTemplate
        self.assetRoute = assetRoute
        self.includeDrafts = includeDrafts
    }

    public init(
        bundleURL: URL,
        routePath: [String] = [],
        pageTemplate: String,
        assetRoute: String = "_asset",
        includeDrafts: Bool = false
    ) throws {
        try self.init(
            contentRoot: bundleURL.deletingLastPathComponent(),
            routePath: routePath,
            pageTemplate: pageTemplate,
            assetRoute: assetRoute,
            includeDrafts: includeDrafts,
            bundleURL: bundleURL
        )
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }
}

public struct BundleContentPageContext: Encodable, Equatable, Sendable {
    public let path: String
    public let title: String
    public let description: String?
    public let updatedAt: String?
    public let contentHTML: String
    public let navTitle: String
    public let isSection: Bool
    public let navigation: [BundleContentNavigationItem]
    public let breadcrumbs: [BundleContentBreadcrumb]
    public let previous: BundleContentLink?
    public let next: BundleContentLink?

    public init(
        path: String,
        title: String,
        description: String?,
        updatedAt: String?,
        contentHTML: String,
        navTitle: String? = nil,
        isSection: Bool = false,
        navigation: [BundleContentNavigationItem] = [],
        breadcrumbs: [BundleContentBreadcrumb] = [],
        previous: BundleContentLink? = nil,
        next: BundleContentLink? = nil
    ) {
        self.path = path
        self.title = title
        self.description = description
        self.updatedAt = updatedAt
        self.contentHTML = contentHTML
        self.navTitle = navTitle ?? title
        self.isSection = isSection
        self.navigation = navigation
        self.breadcrumbs = breadcrumbs
        self.previous = previous
        self.next = next
    }
}

public struct BundleContentRenderTarget: Sendable {
    public let template: String
    public let context: BundleContentPageContext

    public init(template: String, context: BundleContentPageContext) {
        self.template = template
        self.context = context
    }
}

public struct BundleContentAsset: Sendable {
    public let data: Data
    public let mimeType: String
    public let fileName: String

    public init(data: Data, mimeType: String, fileName: String) {
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
    }
}

public actor BundleContentStore {
    private struct PendingPage: Sendable {
        let path: String
        let bundle: BundleContentBundle
        let isSection: Bool
    }

    private struct PageRecord: Sendable {
        let path: String
        let bundle: BundleContentBundle
        let contentHTML: String
        let isSection: Bool
    }

    private struct Snapshot: Sendable {
        let fingerprint: String
        let pages: [String: PageRecord]
    }

    private let configuration: BundleContentConfiguration
    private var snapshot: Snapshot?
    private var failedFingerprint: String?

    public init(configuration: BundleContentConfiguration) {
        self.configuration = configuration
    }

    public func renderTarget(for path: String) throws -> BundleContentRenderTarget {
        let normalizedPath = try normalizedContentPath(path)
        let snapshot = try currentSnapshot()
        guard let page = snapshot.pages[normalizedPath] else {
            throw BundleContentError.notFound(normalizedPath)
        }

        let context = makePage(for: page, from: snapshot)
        let template = normalizedPath.isEmpty
            ? configuration.indexTemplate ?? configuration.pageTemplate
            : page.isSection
                ? configuration.sectionTemplate ?? configuration.pageTemplate
                : configuration.articleTemplate ?? configuration.pageTemplate
        return BundleContentRenderTarget(template: template, context: context)
    }

    public func asset(pagePath: String, assetPath: String) throws -> BundleContentAsset {
        let normalizedPagePath = try normalizedContentPath(pagePath)
        let snapshot = try currentSnapshot()
        guard let page = snapshot.pages[normalizedPagePath] else {
            throw BundleContentError.notFound(normalizedPagePath)
        }

        let components = try Self.normalizedAssetComponents(assetPath)
        let assetsRoot = page.bundle.assetsURL
        let fileURL = components.reduce(assetsRoot) { $0.appendingPathComponent($1, isDirectory: false) }
        guard isDescendant(fileURL, of: assetsRoot),
              FileManager.default.fileExists(atPath: fileURL.path),
              FileManager.default.fileExists(atPath: fileURL.resolvingSymlinksInPath().path)
        else {
            throw BundleContentError.invalidAsset(assetPath)
        }

        let resolvedURL = fileURL.resolvingSymlinksInPath()
        guard isDescendant(resolvedURL, of: assetsRoot.resolvingSymlinksInPath()) else {
            throw BundleContentError.invalidAsset(assetPath)
        }

        let values = try resolvedURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory != true else {
            throw BundleContentError.invalidAsset(assetPath)
        }

        return BundleContentAsset(
            data: try Data(contentsOf: resolvedURL),
            mimeType: Self.mimeType(for: resolvedURL.pathExtension),
            fileName: resolvedURL.lastPathComponent
        )
    }

    public func reload() throws {
        let fingerprint = try contentFingerprint()
        snapshot = try buildSnapshot(fingerprint: fingerprint)
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
            throw BundleContentError.invalidContent("Bundle content root does not exist: \(root.path)")
        }

        var pendingPages: [String: PendingPage] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        var candidates: [URL] = []
        if let bundleURL = configuration.bundleURL {
            candidates = [bundleURL]
        } else {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                throw BundleContentError.invalidContent("Unable to enumerate bundle content.")
            }
            while let candidate = enumerator.nextObject() as? URL {
                let values = try candidate.resourceValues(forKeys: Set(keys))
                guard values.isDirectory == true, candidate.pathExtension == "textbundle" else { continue }
                enumerator.skipDescendants()
                candidates.append(candidate)
            }
        }

        for candidate in candidates {
            let values = try candidate.resourceValues(forKeys: Set(keys))
            guard values.isDirectory == true, candidate.pathExtension == "textbundle" else { continue }

            guard isDescendant(candidate, of: root),
                  isDescendant(candidate.resolvingSymlinksInPath(), of: root.resolvingSymlinksInPath())
            else {
                throw BundleContentError.invalidContent("Bundle escapes the bundle content root: \(candidate.path)")
            }

            let relativeBundlePath = try relativePath(of: candidate, from: root)
            let contentPath = configuration.bundleURL == nil
                ? try contentPath(forBundleRelativePath: relativeBundlePath)
                : ""
            let bundle = try TextBundleReader.attemptToReadBundleContent(at: candidate)
            guard !bundle.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BundleContentError.invalidContent("Bundle has an empty title: \(candidate.path)")
            }
            if bundle.metadata.draft && !configuration.includeDrafts { continue }
            guard pendingPages[contentPath] == nil else {
                throw BundleContentError.invalidContent("Duplicate bundle content path: \(contentPath)")
            }

            pendingPages[contentPath] = PendingPage(
                path: contentPath,
                bundle: bundle,
                isSection: configuration.bundleURL == nil && !contentPath.isEmpty && relativeBundlePath.hasSuffix("/index.textbundle")
            )
        }

        var records: [String: PageRecord] = [:]
        for page in pendingPages.values {
            let html: String
            do {
                html = try MaverickMarkdown.render(
                    page.bundle.markdown,
                    assetURL: { [configuration] source in
                        try Self.assetURL(configuration: configuration, pagePath: page.path, source: source)
                    },
                    linkURL: { [configuration] source in
                        try Self.contentLinkURL(
                            configuration: configuration,
                            source: source,
                            from: page.path,
                            availablePaths: Set(pendingPages.keys)
                        )
                    }
                )
            } catch let error as MaverickMarkdownError {
                switch error {
                case .invalidAssetSource(let source):
                    throw BundleContentError.invalidAsset(source)
                }
            }

            records[page.path] = PageRecord(
                path: page.path,
                bundle: page.bundle,
                contentHTML: html,
                isSection: page.isSection
            )
        }

        return Snapshot(fingerprint: fingerprint, pages: records)
    }

    private func makePage(for page: PageRecord, from snapshot: Snapshot) -> BundleContentPageContext {
        let navigation = navigationItems(from: snapshot.pages, parent: "", currentPath: page.path)
        let flattened = flatten(navigation)
        let currentIndex = flattened.firstIndex { $0.path == page.path }

        return BundleContentPageContext(
            path: page.path,
            title: page.bundle.metadata.title,
            description: page.bundle.metadata.description,
            updatedAt: page.bundle.metadata.updatedAt.map(Self.dateString),
            contentHTML: page.contentHTML,
            navTitle: page.bundle.metadata.navTitle,
            isSection: page.isSection,
            navigation: navigation,
            breadcrumbs: breadcrumbs(for: page, from: snapshot.pages),
            previous: currentIndex.flatMap { index in index > 0 ? flattened[index - 1] : nil },
            next: currentIndex.flatMap { index in index + 1 < flattened.count ? flattened[index + 1] : nil }
        )
    }

    private func navigationItems(
        from records: [String: PageRecord],
        parent: String,
        currentPath: String
    ) -> [BundleContentNavigationItem] {
        records.values
            .filter { $0.path != "" && directParent(of: $0.path) == parent }
            .sorted(by: sortRecords)
            .map { record in
                BundleContentNavigationItem(
                    title: record.bundle.metadata.navTitle ?? record.bundle.metadata.title,
                    path: record.path,
                    url: Self.contentURL(configuration: configuration, path: record.path),
                    children: navigationItems(from: records, parent: record.path, currentPath: currentPath),
                    isCurrent: record.path == currentPath
                )
            }
    }

    private func flatten(_ items: [BundleContentNavigationItem]) -> [BundleContentLink] {
        items.flatMap { item in
            [BundleContentLink(title: item.title, path: item.path, url: item.url)] + flatten(item.children)
        }
    }

    private func breadcrumbs(for page: PageRecord, from records: [String: PageRecord]) -> [BundleContentBreadcrumb] {
        var result = [BundleContentBreadcrumb(title: "Home", url: Self.contentURL(configuration: configuration, path: ""))]
        guard !page.path.isEmpty else { return result }

        let components = page.path.split(separator: "/").map(String.init)
        for index in components.indices {
            let path = components[0...index].joined(separator: "/")
            let title = records[path]?.bundle.metadata.navTitle
                ?? records[path]?.bundle.metadata.title
                ?? components[index]
            result.append(BundleContentBreadcrumb(title: title, url: Self.contentURL(configuration: configuration, path: path)))
        }
        return result
    }

    private func sortRecords(_ lhs: PageRecord, _ rhs: PageRecord) -> Bool {
        if lhs.bundle.metadata.order != rhs.bundle.metadata.order {
            return lhs.bundle.metadata.order < rhs.bundle.metadata.order
        }
        let lhsTitle = lhs.bundle.metadata.navTitle ?? lhs.bundle.metadata.title
        let rhsTitle = rhs.bundle.metadata.navTitle ?? rhs.bundle.metadata.title
        if lhsTitle.localizedStandardCompare(rhsTitle) != .orderedSame {
            return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
        }
        return lhs.path < rhs.path
    }

    private func directParent(of path: String) -> String {
        guard let index = path.lastIndex(of: "/") else { return "" }
        return String(path[..<index])
    }

    private static func contentLinkURL(
        configuration: BundleContentConfiguration,
        source: String,
        from currentPath: String,
        availablePaths: Set<String>
    ) throws -> String? {
        let decoded = source.removingPercentEncoding ?? source
        guard !decoded.isEmpty,
              !decoded.hasPrefix("#"),
              !decoded.hasPrefix("/")
        else { return nil }

        guard let url = URL(string: decoded),
              url.scheme == nil,
              url.host == nil
        else { return nil }

        let pathPart = url.path
        guard !pathPart.isEmpty else { return nil }
        let suffix = (url.query.map { "?\($0)" } ?? "") + (url.fragment.map { "#\($0)" } ?? "")
        let currentDirectory = currentPath.split(separator: "/").dropLast().map(String.init)
        let relativeComponents = pathPart.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        let candidates: [[String]] = [
            currentPath.split(separator: "/").map(String.init) + relativeComponents,
            currentDirectory + relativeComponents,
            relativeComponents,
        ]

        for candidate in candidates {
            let normalized = try normalizedLinkPath(candidate)
            let withoutExtension = normalized.replacingOccurrences(of: ".textbundle", with: "")
            let path = withoutExtension.hasSuffix("/index")
                ? String(withoutExtension.dropLast("/index".count))
                : withoutExtension
            if availablePaths.contains(path) {
                return contentURL(configuration: configuration, path: path) + suffix
            }
        }

        return nil
    }

    private static func normalizedLinkPath(_ components: [String]) throws -> String {
        var normalized: [String] = []
        for component in components {
            switch component {
            case "", ".": continue
            case "..":
                guard !normalized.isEmpty else { throw BundleContentError.invalidContent("Internal link escapes the content root.") }
                normalized.removeLast()
            default:
                guard !component.contains("\\") else { throw BundleContentError.invalidContent("Invalid internal link.") }
                normalized.append(component)
            }
        }
        return normalized.joined(separator: "/")
    }

    private static func contentURL(configuration: BundleContentConfiguration, path: String) -> String {
        let components = configuration.routePath + (path.isEmpty ? [] : path.split(separator: "/").map(String.init))
        return "/" + components.map(urlEncodePathComponent).joined(separator: "/")
    }

    private static func assetURL(
        configuration: BundleContentConfiguration,
        pagePath: String,
        source: String
    ) throws -> String? {
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
            URLQueryItem(name: "page", value: pagePath),
            URLQueryItem(name: "path", value: relative),
        ]
        return components.string
    }

    private func contentFingerprint() throws -> String {
        let root = configuration.contentRoot
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw BundleContentError.invalidContent("Bundle content root does not exist: \(root.path)")
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw BundleContentError.invalidContent("Unable to fingerprint bundle content.")
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
            throw BundleContentError.invalidContent("Bundle is outside the configured content root.")
        }
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }

    private func contentPath(forBundleRelativePath path: String) throws -> String {
        let components = path.split(separator: "/").map(String.init)
        guard let last = components.last, last.hasSuffix(".textbundle") else {
            throw BundleContentError.invalidContent("Invalid textbundle path: \(path)")
        }
        var result = components.dropLast().map { $0 }
        let name = String(last.dropLast(".textbundle".count))
        if name != "index" { result.append(name) }
        return try normalizedContentPath(result.joined(separator: "/"))
    }

    private func normalizedContentPath(_ path: String) throws -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("\\") }) else {
            throw BundleContentError.invalidContent("Invalid bundle content path: \(path)")
        }
        return components.joined(separator: "/")
    }

    private static func normalizedAssetComponents(_ path: String) throws -> [String] {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("\\") }) else {
            throw BundleContentError.invalidAsset(path)
        }
        return components
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

public struct BundleContentRouteCollection<Context: Encodable & Sendable>: RouteCollection, Sendable {
    private let configuration: BundleContentConfiguration
    private let store: BundleContentStore
    private let makeContext: @Sendable (BundleContentPageContext) -> Context

    public init(
        configuration: BundleContentConfiguration,
        store: BundleContentStore? = nil,
        makeContext: @escaping @Sendable (BundleContentPageContext) -> Context
    ) {
        self.configuration = configuration
        self.store = store ?? BundleContentStore(configuration: configuration)
        self.makeContext = makeContext
    }

    public func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped(configuration.routePath.map(PathComponent.constant))

        if !configuration.routePath.isEmpty {
            group.get { req async throws -> View in
                try await render(path: "", request: req)
            }
        }

        group.get("**") { req async throws -> View in
            let path = req.parameters.getCatchall().joined(separator: "/")
            if path == configuration.assetRoute {
                throw Abort(.notFound)
            }
            return try await render(path: path, request: req)
        }

        group.get(PathComponent.constant(configuration.assetRoute)) { req async throws -> Response in
            guard let pagePath = try? req.query.get(String.self, at: ["page"]),
                  let assetPath = try? req.query.get(String.self, at: ["path"])
            else {
                throw Abort(.badRequest)
            }

            do {
                let asset = try await store.asset(pagePath: pagePath, assetPath: assetPath)
                let response = Response(status: .ok)
                response.headers.replaceOrAdd(name: "Content-Type", value: asset.mimeType)
                response.headers.replaceOrAdd(name: "Content-Disposition", value: "inline; filename=\"\(asset.fileName)\"")
                response.body = .init(data: asset.data)
                return response
            } catch let error as BundleContentError {
                throw error.abort
            }
        }
    }

    private func render(path: String, request: Request) async throws -> View {
        do {
            let target = try await store.renderTarget(for: path)
            return try await request.view.render(target.template, makeContext(target.context)).get()
        } catch let error as BundleContentError {
            throw error.abort
        }
    }
}

private extension BundleContentError {
    var abort: Abort {
        switch self {
        case .notFound, .invalidAsset: return Abort(.notFound)
        case .invalidConfiguration, .invalidContent: return Abort(.serviceUnavailable)
        }
    }
}
