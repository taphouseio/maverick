import Foundation

/// Generic names for Maverick's bundle-backed content engine.
///
/// The older `StaticContent*` names remain available as source-compatible aliases.
public typealias BundleContentError = StaticContentError
public typealias BundleContentConfiguration = StaticContentConfiguration
public typealias BundleContentPageContext = StaticContentPageContext
public typealias BundleContentRenderTarget = StaticContentRenderTarget
public typealias BundleContentAsset = StaticContentAsset
public typealias BundleContentStore = StaticContentStore
public typealias BundleContentRouteCollection<Context: Encodable & Sendable> = StaticContentRouteCollection<Context>

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
