//
//  StaticPageController.swift
//  App
//
//  Created by Jared Sorge on 5/28/18.
//

import Foundation
import Leaf
import MaverickModels
import PathKit
import Vapor

struct StaticPageRouter: RouteCollection {
    private static var site: SiteConfig?
    private static var router: RoutesBuilder?
    private static var pageManager = StaticPageManager()
    
    init(siteConfig site: SiteConfig) {
        StaticPageRouter.site = site
    }
    
    func boot(routes router: RoutesBuilder) throws {
        StaticPageRouter.router = router
        try StaticPageRouter.updateStaticRoutes()
    }
    
    static func updateStaticRoutes() throws {
        guard let router = router, let config = site else { return }

        let newPages = try pageManager.updatePaths()
        for page in newPages {
            router.get(PathComponent.constant(page)) { req async throws -> View in
                let leaf = req.leaf
                let post = try StaticPageController.fetchStaticPage(named: page, in: .pages, for: StaticPageRouter.site!)
                let outputPage = Page(style: .single(post: post), site: config, title: post.title ?? config.title)
                return try await leaf.render("post", outputPage).get()
            }
        }
        
        //TODO: Figure out if a route can be removed
    }
}

struct StaticPageController {
    static func fetchStaticPage(named pageName: String, in location: Location,
                                for site: SiteConfig) throws -> Post
    {
        let base = try FileReader.attemptToReadFile(named: pageName, in: location)
        let assetsPath = PathHelper.makeBundleAssetsPath(filename: pageName, location: .pages)
        let formattedContent = try FileProcessor.processMarkdownText(base.content, for: assetsPath)
        
        var postURL = site.url
        if let component = location.webPathComponent {
            postURL.appendPathComponent(component)
        }
        postURL.appendPathComponent(pageName)
        
        let post = Post(url: "\(postURL)",
                        title: base.frontMatter.title,
                        content: formattedContent,
                        frontMatter: base.frontMatter,
                        path: nil)
        return post
    }
}

private struct StaticPageManager {
    typealias PageName = String
    private var registeredPages = [PageName]()

    mutating func updatePaths() throws -> [PageName] {
        func isLegalPageName(_ name: PageName) -> Bool {
            return name.starts(with: ".") == false
        }

        let dirPath = PathHelper.root + Path("Public/\(Location.pages.rawValue)")
        var newPages = [PageName]()
        do {
            let children = try dirPath.children()
            let pages = children.map({ $0.lastComponentWithoutExtension }).filter({ isLegalPageName($0) })
            for page in pages {
                guard registeredPages.contains(page) == false else { continue }
                registeredPages.append(page)
                newPages.append(page)
            }
        } catch {
            return newPages
        }

        return newPages
    }
}
