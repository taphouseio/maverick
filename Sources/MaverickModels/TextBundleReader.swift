//
//  TextBundleReader.swift
//  MaverickModels
//
//  Created by Jared Sorge on 11/5/19.
//

import Foundation
import PathKit
import Yams

public enum FileReaderError: Error {
    case unreadableFile(String)
}

public struct TextBundleReader {
    public static func attemptToReadFile(at bundlePath: String) throws -> BasePost {
        let path = Path(bundlePath)
        let infoPath = path + Path("info.json")
        let textPath = path + Path("text.md")

        let markdown: String = try textPath.read()
        let bundleData: Data = try infoPath.read()

        let frontMatter: FrontMatter
        let content: String
        if let bundleInfo = BundleInfo(json: bundleData), let bundledFrontMatter = bundleInfo.frontMatter {
            frontMatter = bundledFrontMatter
            content = markdown
        } else if let legacy = try Self.legacyFrontMatter(in: markdown) {
            frontMatter = legacy.frontMatter
            content = legacy.content
        } else {
            throw FileReaderError.unreadableFile(bundlePath)
        }

        let post = BasePost(frontMatter: frontMatter, content: content)
        return post
    }

    public static func attemptToReadBundleContent(at bundleURL: URL) throws -> BundleContentBundle {
        let path = bundleURL.standardizedFileURL
        let infoURL = path.appendingPathComponent("info.json", isDirectory: false)
        let textURL = path.appendingPathComponent("text.md", isDirectory: false)

        let markdown = try String(contentsOf: textURL, encoding: .utf8)
        let bundleData = try Data(contentsOf: infoURL)

        guard let bundleInfo = BundleInfo(json: bundleData),
              let metadata = bundleInfo.bundleContentMetadata
        else {
            throw FileReaderError.unreadableFile(bundleURL.path)
        }

        return BundleContentBundle(
            metadata: metadata,
            markdown: markdown,
            bundleURL: path,
            assetsURL: path.appendingPathComponent("assets", isDirectory: true)
        )
    }

    private static func legacyFrontMatter(in markdown: String) throws -> (frontMatter: FrontMatter, content: String)? {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return nil }
        let separator = markdown.contains("\r\n") ? "\r\n---\r\n" : "\n---\n"
        guard let end = markdown.range(of: separator, range: markdown.index(markdown.startIndex, offsetBy: 4)..<markdown.endIndex) else {
            return nil
        }

        let yaml = String(markdown[markdown.index(markdown.startIndex, offsetBy: 4)..<end.lowerBound])
        guard let frontMatter = try? YAMLDecoder().decode(FrontMatter.self, from: yaml) else { return nil }
        let content = String(markdown[end.upperBound...])
        return (frontMatter, content)
    }
}
