//
//  StaticPageRouter.swift
//  Maverick
//
//  Created by Jared Sorge on 5/28/18.
//

import Foundation
import Leaf
import MaverickLib
import MaverickModels
import Vapor

struct StaticPageRouter: RouteCollection, Sendable {
    // These are set once during boot and accessed from the main server context
    nonisolated(unsafe) private static var site: SiteConfig?
    nonisolated(unsafe) private static var router: RoutesBuilder?
    nonisolated(unsafe) private static var pageManager = StaticPageManager()

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
