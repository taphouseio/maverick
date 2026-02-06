//
//  PostConverter.swift
//  Maverick
//
//  Created by Jared Sorge on 6/6/18.
//

import Foundation
import MaverickLib
import MaverickModels
import Micropub
import TextBundleify
import PathKit

struct PostConverter {
    static func saveMicropubPost(_ post: MicropubBlogPostRequest) throws -> String {
        let blogPost = makeWholeFileContents(fromMicropub: post)
        let postPath = PostPath.from(micropub: post)
        let mdPath = PathHelper.incomingPostPath + Path("\(postPath.asFilename).md")
        try PathHelper.prepTheTemporaryPaths()
        try mdPath.write(blogPost)

        try TextBundleify.start(in: PathHelper.incomingPostPath, pathToAssets: PathHelper.incomingMediaPath)
        let incomingBundlePath = PathHelper.incomingPostPath + Path("\(postPath.asFilename).textbundle")
        let destinationBundlePath = PathHelper.postFolderPath + Path("\(postPath.asFilename).textbundle")
        if destinationBundlePath.exists {
            try? destinationBundlePath.delete()
        }
        try incomingBundlePath.move(destinationBundlePath)

        try FeedOutput.makeAllTheFeeds()
        return postPath.asURIPath
    }
}

private func makeWholeFileContents(fromMicropub micropub: MicropubBlogPostRequest) -> String {
    var content = """
    ---
    title: \(micropub.name ?? "")
    date: \(FrontMatter.dateFormatter.string(from: micropub.date))
    category: \(micropub.category?.joined(separator: ", ") ?? "")
    ---
    \(micropub.content)
    """

    if let photo = micropub.photo {
        content += "\n![](\(photo))"
    }

    return content
}

private extension PostPath {
    static func from(micropub post: MicropubBlogPostRequest) -> PostPath {
        let calendar = Calendar.current
        let date = post.date
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        var slug = [String]()
        for word in post.content.split(separator: " ") {
            guard slug.count < 6 else { break }
            var slugComponent = String(word).lowercased()
                .replacingOccurrences(of: "!", with: "")
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            if slugComponent.contains(".") {
                let exploded = slugComponent.split(separator: ".")
                slugComponent = String(exploded[0])
            }
            slug.append(slugComponent)
        }

        let path = PostPath(year: year, month: month, day: day, slug: slug.joined(separator: "-"))
        return path
    }
}
