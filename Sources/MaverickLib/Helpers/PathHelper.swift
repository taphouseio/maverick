//
//  PathHelper.swift
//  App
//
//  Created by Jared Sorge on 6/2/18.
//

import Foundation
@preconcurrency import PathKit
import Vapor

enum Location: String {
    case pages = "_pages"
    case posts = "_posts"
    case drafts = "_drafts"
    
    var webPathComponent: String? {
        switch self {
        case .drafts:
            return "draft"
        default:
            return nil
        }
    }
}

struct PathHelper: Sendable {
    static func makeBundleAssetsPath(filename: String, location: Location) -> String {
        return "/\(location.rawValue)/\(filename).textbundle"
    }

    // Path properties are initialized once at startup and never mutated
    nonisolated(unsafe) static let root: Path = {
        let root = Path(DirectoryConfiguration.detect().workingDirectory)

        if isDebug() {
            return root + Path("_dev")
        }

        return root
    }()

    nonisolated(unsafe) static let publicFolderPath: Path = {
        return root + Path("Public")
    }()

    nonisolated(unsafe) static let postFolderPath: Path = {
        let postsPath = publicFolderPath + Path(Location.posts.rawValue)
        return postsPath
    }()

    static func pathsForAllPosts() throws -> [Path] {
        let allPaths = try postFolderPath.children()
            .sorted(by: { $0.lastComponentWithoutExtension > $1.lastComponentWithoutExtension })
        return allPaths
    }

    static func prepTheTemporaryPaths() throws {
        try incomingPostPath.mkpath()
        try incomingMediaPath.mkpath()
    }

    nonisolated(unsafe) static let incomingFolderPath: Path = {
        return publicFolderPath + Path("incoming")
    }()

    nonisolated(unsafe) static let incomingPostPath: Path = {
        return incomingFolderPath + Path("posts")
    }()

    nonisolated(unsafe) static let incomingMediaPath: Path = {
        return incomingFolderPath + Path("media")
    }()
}
