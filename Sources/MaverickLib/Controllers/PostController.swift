//
//  PostController.swift
//  App
//
//  Created by Jared Sorge on 5/28/18.
//

import Foundation
import MaverickModels
import Markdown

public enum PostControllerError: Error {
    case doesNotContainRequestedTag
}

public struct PostController: Sendable {
    public init(site: SiteConfig) {
        _site = site
    }

    public func fetchPost(withPath path: PostPath, outputtingFor output: TextOutputType, tag: Tag? = nil) throws -> Post {
        let base = try FileReader.attemptToReadFile(named: path.asFilename, in: .posts)

        if let tag = tag {
            guard base.frontMatter.tags.contains(tag) else { throw PostControllerError.doesNotContainRequestedTag }
        }

        let formattedContent = try base.makeContent(for: output, path: path, site: _site)
        let title = base.frontMatter.title

        let post = Post(url: "\(_site.url)\(path.asURIPath)",
                        title: title,
                        content: formattedContent,
                        frontMatter: base.frontMatter,
                        path: path)
        return post
    }

    //MARK: - Private
    private let _site: SiteConfig
}

private extension BasePost {
    func makeContent(for outputType: TextOutputType, path: PostPath, site: SiteConfig) throws -> String {
        switch outputType {
        case .fullText:
            let assetsPath = PathHelper.makeBundleAssetsPath(filename: path.asFilename, location: .posts)
            let formattedContent = try FileProcessor.processMarkdownText(content, for: assetsPath)
            return formattedContent
        case .microblog:
            if isMicropost {
                return try makeMicropostContent(with: path, site: site)
            }
            else {
                return try makeContentForLongPostInMicroblogFeed(title: frontMatter.title, path: path, site: site)
            }
        }
    }

    private var isMicropost: Bool {
        let hasTitle = frontMatter.title != nil
        return hasTitle == false && frontMatter.isMicroblog
    }

    private var microPostMaxLength: Int { return 280 }

    private func makeContentForLongPostInMicroblogFeed(title: String?, path: PostPath, site: SiteConfig) throws -> String {
        let postHref = "\(site.url.appendingPathComponent(path.asURIPath))"
        var output = "New post from \(site.title): "

        if let title = title {
            output.append(title)
        }
        else {
            output.append(postHref)
        }

        output.append("""
        \(postHref)
        """)

        output = HTMLFormatter.format(output)
        return output
    }

    private func makeMicropostContent(with path: PostPath, site: SiteConfig) throws -> String {
        var output = ""

        let padding = 5 // the number of characters represenging the `...\n\n` part of the post
        let postHref = "\(site.url.appendingPathComponent(path.asURIPath))"
        let postCharactersToTake = microPostMaxLength - postHref.count - padding
        let firstPart = String(content.prefix(postCharactersToTake))

        output = """
        \(firstPart)...

        \(postHref)
        """

        output = HTMLFormatter.format(output)
        return output
    }
}
