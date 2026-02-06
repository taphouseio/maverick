//
//  TagRouteCollection.swift
//  Maverick
//
//  Created by Jared Sorge on 3/4/19.
//

import Foundation
import Leaf
import MaverickLib
import MaverickModels
import Vapor

final class TagRouteCollection: RouteCollection, Sendable {
    init() {}

    func boot(routes: RoutesBuilder) throws {
        SiteContentChangeResponderManager.shared.registerResponder(TagCache.shared)

        routes.get("tag", ":tag") { req async throws -> View in
            let siteConfig = try SiteConfigController.fetchSite()

            let leaf = req.leaf
            let tag = try req.parameters.require("tag")
            let postList = try TagListController.fetchPostsForTag(tag, pageNumber: nil, siteConfig: siteConfig)
            let outputPage = Page(style: .list(list: postList), site: siteConfig,
                                  title: siteConfig.title)
            return try await leaf.render("index", outputPage).get()
        }

        routes.get("tag", ":tag", ":page") { req async throws -> View in
            let siteConfig = try SiteConfigController.fetchSite()

            let leaf = req.leaf
            let tag = try req.parameters.require("tag")
            let page = try req.parameters.require("page", as: Int.self)
            let postList = try TagListController.fetchPostsForTag(tag, pageNumber: page, siteConfig: siteConfig)
            let outputPage = Page(style: .list(list: postList), site: siteConfig,
                                  title: siteConfig.title)
            return try await leaf.render("index", outputPage).get()
        }
    }
}
