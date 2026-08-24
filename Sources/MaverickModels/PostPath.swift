//
//  PostPath.swift
//  App
//
//  Created by Jared Sorge on 6/1/18.
//

import Foundation

public struct PostPath: Codable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let slug: String
    
    public var asURIPath: String {
        return "/\(year)/\(String(format: "%02d", month))/\(String(format: "%02d", day))/\(slug)"
    }
    
    public var asFilename: String {
        return "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))-\(slug)"
    }
    
    public init(year: Int, month: Int, day: Int, slug: String) {
        self.year = year
        self.month = month
        self.day = day
        self.slug = slug
    }

    public static func < (lhs: PostPath, rhs: PostPath) -> Bool {
        if lhs.year < rhs.year {
            return true
        }
        
        if lhs.month < rhs.month {
            return true
        }
        
        if lhs.day < rhs.day {
            return true
        }
        
        return false
    }
    
    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case day
        case slug
    }
}
