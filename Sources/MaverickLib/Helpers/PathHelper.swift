//
//  PathHelper.swift
//  App
//
//  Created by Jared Sorge on 6/2/18.
//

import Foundation
@preconcurrency import PathKit

public enum Location: String, Sendable {
    case pages = "_pages"
    case posts = "_posts"
    case drafts = "_drafts"

    public var webPathComponent: String? {
        switch self {
        case .drafts:
            return "draft"
        default:
            return nil
        }
    }
}

public struct PathHelper: Sendable {
    public static func makeBundleAssetsPath(filename: String, location: Location) -> String {
        return "/\(location.rawValue)/\(filename).textbundle"
    }

    // Path properties are initialized once at startup and never mutated
    nonisolated(unsafe) public static let root: Path = {
        let root = Path(FileManager.default.currentDirectoryPath)

        if isDebug() {
            return root + Path("_dev")
        }

        return root
    }()

    nonisolated(unsafe) public static let publicFolderPath: Path = {
        return root + Path("Public")
    }()

    nonisolated(unsafe) public static let postFolderPath: Path = {
        let postsPath = publicFolderPath + Path(Location.posts.rawValue)
        return postsPath
    }()

    public static func pathsForAllPosts() throws -> [Path] {
        let allPaths = try postFolderPath.children()
            .sorted(by: { $0.lastComponentWithoutExtension > $1.lastComponentWithoutExtension })
        return allPaths
    }

    public static func prepTheTemporaryPaths() throws {
        try incomingPostPath.mkpath()
        try incomingMediaPath.mkpath()
    }

    nonisolated(unsafe) public static let incomingFolderPath: Path = {
        return publicFolderPath + Path("incoming")
    }()

    nonisolated(unsafe) public static let incomingPostPath: Path = {
        return incomingFolderPath + Path("posts")
    }()

    nonisolated(unsafe) public static let incomingMediaPath: Path = {
        return incomingFolderPath + Path("media")
    }()
}
