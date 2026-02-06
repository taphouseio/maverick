//
//  StaticPageController.swift
//  App
//
//  Created by Jared Sorge on 5/28/18.
//

import Foundation
import MaverickModels
import PathKit

public struct StaticPageController: Sendable {
    public static func fetchStaticPage(named pageName: String, in location: Location,
                                for site: SiteConfig) throws -> Post
    {
        let base = try FileReader.attemptToReadFile(named: pageName, in: location)
        let assetsPath = PathHelper.makeBundleAssetsPath(filename: pageName, location: location)
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

public struct StaticPageManager: Sendable {
    public typealias PageName = String
    private var registeredPages = [PageName]()

    public init() {}

    public mutating func updatePaths() throws -> [PageName] {
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
