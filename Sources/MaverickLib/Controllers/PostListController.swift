//
//  PostListController.swift
//  App
//
//  Created by Jared Sorge on 5/29/18.
//

import Foundation
import MaverickModels
import PathKit

public struct PostListController: Sendable {
    public static func fetchPostList(forPageNumber pageNumber: Int, config: SiteConfig) throws -> PostList {
        let allPostPaths = try PathHelper.pathsForAllPosts()
        let postsPaths = allPostPaths.compactMap({ PostPath(path: $0) })

        let batchStart = (pageNumber - 1) * config.batchSize
        var batchEnd = batchStart + config.batchSize
        if batchEnd > allPostPaths.count {
            batchEnd = allPostPaths.count - 1
        }
        let batchRange = batchStart..<batchEnd
        let neededPaths = Array(postsPaths[batchRange])

        let postController = PostController(site: config)
        let posts = neededPaths
                    .compactMap({ try? postController.fetchPost(withPath: $0, outputtingFor: .fullText) })
                    .sorted(by: { $0.date > $1.date })

        var pageCount = allPostPaths.count / config.batchSize
        if allPostPaths.count % config.batchSize != 0 {
            pageCount += 1
        }

        let olderLink: String?
        if pageNumber + 1 <= pageCount {
            olderLink = "/page/\(pageNumber + 1)"
        }
        else {
            olderLink = nil
        }

        let newerLink: String?
        if pageNumber - 1 == 1 {
            newerLink = "/"
        }
        else if pageNumber == 1 {
            newerLink = nil
        }
        else {
            newerLink = "/page/\(pageNumber - 1)"
        }

        let pagination = Pagination(newerLink: newerLink,
                                    olderLink: olderLink,
                                    pageNumber: "\(pageNumber) of \(pageCount)")

        let postList = PostList(posts: posts, pagination: pagination)
        return postList
    }
}
