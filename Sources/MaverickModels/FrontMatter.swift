//
//  FrontMatter.swift
//  MaverickModels
//
//  Created by Jared Sorge on 2/21/19.
//

import Foundation

public typealias Tag = String

/// Metadata about a post
public struct FrontMatter: Codable {
    /// The date format used in all content
    nonisolated(unsafe) public static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [ .withInternetDateTime ]
        return formatter
    }()

    /// The original date formatter used for older posts. I think this is the format that Ghost uses.
    nonisolated(unsafe) private static let deprecatedFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withYear,
            .withMonth,
            .withDay,
            .withDashSeparatorInDate,
            .withTime,
            .withSpaceBetweenDateAndTime,
            .withColonSeparatorInTime
        ]
        return formatter
    }()

    /// Is the post a micro-post
    public let isMicroblog: Bool
    /// The title of the content
    public let title: String?
    /// The layout of the content (this isn't used currently but could be in the future if needed)
    public let layout: String?
    /// The unique identifier for the content
    public let guid: String?
    /// The date of the post
    public let date: Date
    /// Defines whether the attached content is a post or a page
    public let isStaticPage: Bool
    /// A short description of the content (useful for things like Twitter cards)
    public let shortDescription: String
    /// The name of the file
    public let filename: String?
    /// The tags that a post belongs to
    public let tags: [Tag]

    private enum CodingKeys: String, CodingKey {
        case isMicroblog = "microblog"
        case title = "title"
        case layout = "layout"
        case guid = "guid"
        case date = "date"
        case isStaticPage = "staticpage"
        case shortDescription = "shortdescription"
        case filename = "filename"
        case tags = "tags"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isMicroblog = try container.decodeIfPresent(Bool.self, forKey: .isMicroblog) ?? false
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.layout = try container.decodeIfPresent(String.self, forKey: .layout)
        self.guid = try container.decodeIfPresent(String.self, forKey: .guid)
        self.isStaticPage = try container.decodeIfPresent(Bool.self, forKey: .isStaticPage) ?? false
        self.shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription) ?? ""
        self.filename = try container.decodeIfPresent(String.self, forKey: .filename)

        // Dates are finicky.
        // Dates now need to be in internet time (RFC 3339)
        // We initially expected them to come in in `2018-07-11 06:29:36` format
        // But they could also come in `2018-08-01T01:57:13Z` format
        let dateString = try container.decode(String.self, forKey: .date)
        let date: Date
        if let parsedDate = FrontMatter.dateFormatter.date(from: dateString) {
            date = parsedDate
        }
        else if let parsedDate = FrontMatter.deprecatedFormatter.date(from: dateString) {
            date = parsedDate
        }
        else if let parsedDate = ISO8601DateFormatter().date(from: dateString) {
            date = parsedDate
        }
        else {
            date = Date()
        }
        self.date = date

        let tags = try container.decodeIfPresent([Tag].self, forKey: .tags)
        self.tags = tags ?? []
    }

    public init(isMicroblog: Bool, title: String?, layout: String?, guid: String?, date: Date,
                isStaticPage: Bool, shortDescription: String, filename: String?, tags: [Tag] = [])
    {
        self.isMicroblog = isMicroblog
        self.title = title
        self.layout = layout
        self.guid = guid
        self.date = date
        self.isStaticPage = isStaticPage
        self.shortDescription = shortDescription
        self.filename = filename
        self.tags = tags
    }
}

extension FrontMatter {
    public static func emptyTemplate(date: Date, filename: String, title: String) -> FrontMatter {
        return FrontMatter(isMicroblog: false, title: title,
                           layout: "post", guid: nil, date: date, isStaticPage: false,
                           shortDescription: "<Short Description Goes Here>", filename: filename)
    }
}
