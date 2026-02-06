//
//  PostListRouteCollection.swift
//  Maverick
//
//  Created by Jared Sorge on 5/29/18.
//

import Foundation
import Leaf
import MaverickLib
import MaverickModels
import Vapor

struct PostListRouteCollection: RouteCollection {
    private let config: SiteConfig

    init(config: SiteConfig) {
        self.config = config
    }

    func boot(routes: RoutesBuilder) throws {
        @Sendable func fetchPostList(for page: Int, config: SiteConfig) throws -> Page {
            let postList = try PostListController.fetchPostList(forPageNumber: page, config: config)
            let outputPage = Page(style: .list(list: postList), site: config, title: config.title)
            return outputPage
        }

        // Home
        routes.get("") { req async throws -> View in
            let config = try SiteConfigController.fetchSite()
            let leaf = req.leaf
            let page = try fetchPostList(for: 1, config: config)
            return try await leaf.render("index", page).get()
        }

        // Archive
        routes.get("page", ":page") { req async throws -> View in
            let config = try SiteConfigController.fetchSite()
            let leaf = req.leaf
            let page = try req.parameters.require("page", as: Int.self)
            let outputPage = try fetchPostList(for: page, config: config)
            return try await leaf.render("index", outputPage).get()
        }
    }
}
