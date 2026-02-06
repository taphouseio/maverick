//
//  TagCache.swift
//  MaverickLib
//
//  Created by Jared Sorge on 3/4/19.
//

import Foundation
import MaverickModels
import PathKit

public final class TagCache: @unchecked Sendable {
    private var storage: [Tag: [PostPath]] = [:]

    public static let shared = TagCache()

    public init() {
        guard let config = try? SiteConfigController.fetchSite() else { return }
        self.respondToSiteContentChange(site: config)
    }

    public func allPaths(for tag: String) -> [PostPath] {
        return storage[tag] ?? []
            .sorted()
    }

    private func reset() {
        storage.removeAll()
    }

    private func addPath(_ path: PostPath, for tag: Tag) {
        var stored = storage[tag] ?? []
        stored.append(path)
        storage[tag] = stored
    }
}

extension TagCache: SiteContentChangeResponder {
    public func respondToSiteContentChange(site: SiteConfig) {
        reset()

        guard let allPostPaths = try? PathHelper.pathsForAllPosts().compactMap({ PostPath(path: $0) }) else { return }

        for path in allPostPaths {
            guard let base = try? FileReader.attemptToReadFile(named: path.asFilename, in: .posts),
                base.frontMatter.tags.isEmpty == false else {
                    continue
            }

            base.frontMatter.tags.forEach({ addPath(path, for: $0) })
        }
    }
}

public struct TagListController: Sendable {
    public static func fetchPostsForTag(_ tag: Tag, pageNumber: Int?, siteConfig: SiteConfig) throws -> PostList {
        let postPaths = TagCache.shared.allPaths(for: tag)

        var pageCount = postPaths.count / siteConfig.batchSize
        if postPaths.count % siteConfig.batchSize != 0 {
            pageCount += 1
        }

        let neededPaths: [PostPath]
        let currentPage = pageNumber ?? 1
        if pageCount > 1 {
            let batchStart = (currentPage - 1) * siteConfig.batchSize
            var batchEnd = batchStart + siteConfig.batchSize
            if batchEnd > postPaths.count {
                batchEnd = postPaths.count - 1
            }

            let batchRange = batchStart..<batchEnd
            neededPaths = Array(postPaths[batchRange])
        }
        else {
            neededPaths = postPaths
        }

        let olderLink: String?
        if currentPage + 1 <= pageCount {
            olderLink = "/tag/\(tag)/\(currentPage + 1)"
        }
        else {
            olderLink = nil
        }

        let newerLink: String?
        if currentPage - 1 == 1 {
            newerLink = "/tag/\(tag)"
        }
        else if currentPage == 1 {
            newerLink = nil
        }
        else {
            newerLink = "/tag/\(tag)/\(currentPage - 1)"
        }


        let postController = PostController(site: siteConfig)
        let posts = neededPaths
            .compactMap({ try? postController.fetchPost(withPath: $0, outputtingFor: .fullText) })
            .sorted(by: { $0.date > $1.date })

        let pagination = Pagination(newerLink: newerLink,
                                    olderLink: olderLink,
                                    pageNumber: "\(pageNumber ?? 1) of \(pageCount)")

        let postList = PostList(posts: posts, pagination: pagination)
        return postList
    }
}
