//
//  JSONFeedGenerator.swift
//  App
//
//  Created by Jared Sorge on 6/5/18.
//

import Foundation
import MaverickModels
import Markdown

struct JSONFeedGenerator: FeedGenerator {
    static func makeFeed(from posts: [Post], for site: SiteConfig, goingTo type: TextOutputType)
        throws -> String
    {
        let items: [JSONFeed.Item] = posts.compactMap({
            let url = site.url.appendingPathComponent($0.path!.asURIPath)
            return JSONFeed.Item(id: url.absoluteString, url: url, title: $0.title, content: $0.content,
                                 date: $0.date)
        })
        
        let feed = JSONFeed(title: site.title,
                            feedURL: site.url.appendingPathComponent(outputFileName(forType: type)),
                            homepageURL: site.url, items: items)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(feed)
        let output = String(data: data, encoding: .utf8)
        return output ?? ""
    }
    
    static func outputFileName(forType type: TextOutputType) -> String {
        switch type {
        case .fullText:
            return "feed.json"
        case .microblog:
            return "microblog-feed.json"
        }
    }
}

private struct JSONFeed: Codable {
    private(set) var version: String = {
        return "1"
    }()
    let title: String
    let feedURL: URL
    let homepageURL: URL
    let items: [Item]
    
    init(title: String, feedURL: URL, homepageURL: URL, items: [Item]) {
        self.title = title
        self.feedURL = feedURL
        self.homepageURL  = homepageURL
        self.items = items
    }
    
    private enum CodingKeys: String, CodingKey {
        case version
        case title
        case feedURL = "feed_url"
        case homepageURL = "home_page_url"
        case items
    }
    
    struct Item: Codable {
        let id: String
        let url: URL
        let title: String?
        let content: String
        let date: Date
        
        private enum CodingKeys: String, CodingKey {
            case id
            case url
            case title
            case content = "content_html"
            case date = "date_published"
        }
    }
}
