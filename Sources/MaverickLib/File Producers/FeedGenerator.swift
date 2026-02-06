//
//  FeedGenerator.swift
//  App
//
//  Created by Jared Sorge on 6/3/18.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MaverickModels
import PathKit

protocol FeedGenerator {
    static func makeFeed(from posts: [Post], for site: SiteConfig, goingTo type: TextOutputType) throws -> String
    static func outputFileName(forType type: TextOutputType) -> String
}

public struct FeedOutput: Sendable {
    /// Generates the conttent of all the feeds
    ///
    /// - Returns: True if the feed content has changed
    /// - Throws: Errors are propagated from implementing other functions that throw
    @discardableResult
    public static func makeAllTheFeeds() throws -> Bool {
        let site = try SiteConfigController.fetchSite()

        var changed = false
        for (generator, outputType) in allOutputsAndGenerators {
            let posts = try postsToGenerate(for: outputType)
            let filename = generator.outputFileName(forType: outputType)

            let fileText = try generator.makeFeed(from: posts, for: site, goingTo: outputType)
            let outputPath = PathHelper.publicFolderPath + Path(filename)

            if outputPath.exists && changed == false {
                let existingTextData = try outputPath.read()
                let existingText = String(data: existingTextData, encoding: .utf8)
                changed = fileText != existingText
            }
            else {
                changed = true
            }


            try outputPath.write(fileText)
        }

        if changed {
            try SiteContentChangeResponderManager.shared.respondToContentChange()
        }

        return changed
    }

    static func postsToGenerate(for outputType: TextOutputType) throws -> [Post] {
        let site = try SiteConfigController.fetchSite()
        let paths = try PathHelper.pathsForAllPosts()
        let controller = PostController(site: site)

        var posts = [Post]()
        for path in paths {
            guard posts.count < site.feedSize else { break }
            guard let postPath = PostPath(path: path) else { break }
            let post = try controller.fetchPost(withPath: postPath, outputtingFor: outputType)
            posts.append(post)
        }

        return posts.sorted(by: { $0.date > $1.date })
    }

    static var allOutputsAndGenerators: [(generator: FeedGenerator.Type, output: TextOutputType)] {
        var output = [(generator: FeedGenerator.Type, output: TextOutputType)]()

        for generator in allGenerators {
            for text in TextOutputType.allCases {
                output.append((generator: generator, output: text))
            }
        }

        return output
    }

    private static var allGenerators: [FeedGenerator.Type] {
        return [JSONFeedGenerator.self, RSSFeedGenerator.self]
    }
}

public struct SitePinger: SiteContentChangeResponder {
    public init() {}

    public func respondToSiteContentChange(site: SiteConfig) {
        guard let pingURLS = site.sitesToPing else { return }

        for url in pingURLS {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            URLSession.shared.dataTask(with: request).resume()
        }
    }
}
