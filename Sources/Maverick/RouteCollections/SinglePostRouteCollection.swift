//
//  SinglePostRouteCollection.swift
//  Maverick
//
//  Created by Jared Sorge on 5/28/18.
//

import Foundation
import Leaf
import MaverickLib
import MaverickModels
import Vapor

struct SinglePostRouteCollection: RouteCollection {
    let config: SiteConfig

    init(config: SiteConfig) {
        self.config = config
    }

    func boot(routes: RoutesBuilder) throws {
        @Sendable func attemptToFindPost(withSlug slug: String, for req: Request) async throws -> Response {
            let posts = try PathHelper.pathsForAllPosts()
            guard let filePath = posts.filter({ $0.lastComponentWithoutExtension.contains(slug) }).first,
                let postPath = PostPath(path: filePath) else {
                let response = Response(status: .notFound)
                return response
            }

            let urlPath = self.config.url.appendingPathComponent(postPath.asURIPath)
            let response = req.redirect(to: urlPath.absoluteString, redirectType: .permanent)
            return response
        }

        routes.get(":year", ":month", ":day", ":slug") { req async throws -> Response in
            let year = try req.parameters.require("year", as: Int.self)
            let month = try req.parameters.require("month", as: Int.self)
            let day = try req.parameters.require("day", as: Int.self)
            let slug = try req.parameters.require("slug")

            let leaf = req.leaf
            let path = PostPath(year: year, month: month, day: day, slug: slug)

            do {
                let postController = PostController(site: self.config)
                let post = try postController.fetchPost(withPath: path, outputtingFor: .fullText)
                let outputPage = Page(style: .single(post: post), site: self.config, title: post.title ?? self.config.title)

                let response = Response()
                response.headers.contentType = .html
                let view = try await leaf.render("post", outputPage).get()

                let data = Data(view.data.readableBytesView)
                response.body = Response.Body(data: data)
                return response
            }
            catch {
                return try await attemptToFindPost(withSlug: path.slug, for: req)
            }
        }

        routes.get("draft", ":slug") { req async throws -> Response in
            let leaf = req.leaf
            guard let slug = req.parameters.get("slug") else {
                let response = Response(status: .notFound)
                return response
            }

            do {
                let post = try StaticPageController.fetchStaticPage(named: slug, in: .drafts, for: self.config)
                let outputPage = Page(style: .single(post: post), site: self.config,
                                      title: post.title ?? self.config.title)

                let response = Response()
                response.headers.contentType = .html
                let view = try await leaf.render("post", outputPage).get()
                let data = Data(view.data.readableBytesView)
                response.body = Response.Body(data: data)
                return response
            }
            catch {
                return try await attemptToFindPost(withSlug: slug, for: req)
            }
        }
    }
}
