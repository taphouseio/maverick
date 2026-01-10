//
//  FileProcessor.swift
//  App
//
//  Created by Jared Sorge on 6/2/18.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MaverickModels
import PathKit
import Markdown

struct FileProcessor {
    static func processMarkdownText(_ markdown: Markdown, for urlPath: String) throws -> String {
        var processedText = markdown
        processedText = relinkImagesInText(processedText, urlPath: urlPath)
        processedText = HTMLFormatter.format(processedText)
        return processedText
    }

    static func findImagesInText(_ markdown: Markdown) -> [NSTextCheckingResult] {
        // TODO: Can the Markdown.Document type be used to get the images from text instead?

        // The \ characters have to be escaped, so the pattern is actually:
        // !\[[^\]]*\]\((?<filename>.*?)(?=\"|\))(?<optionalpart>\".*\")?\)
        let pattern = """
        !\\[[^\\]]*\\]\\((?<filename>.*?)(?=\\"|\\))(?<optionalpart>\\".*\\")?\\)
        """

        let regex = try! NSRegularExpression.init(pattern: pattern, options: [])
        let matches = regex.matches(in: markdown, options: [], range: NSRange(location: 0,
                                                                              length: markdown.count))

        return matches
    }
    
    static func attemptToLinkImagesToPosts(imagePaths paths: [Path]) throws {
        func textbundleNameThatContainsImage(named filename: String) throws -> String? {
            let task = Process()
            let pipe = Pipe()
            
            task.executableURL = URL(string: "/usr/bin/grep")
            task.arguments = ["-r", filename, "/Users/jsorge/Develop/maverick/Public/_posts"]
            task.standardOutput = pipe
            try task.run()
            
            let handle = pipe.fileHandleForReading
            let data = handle.readDataToEndOfFile()
            guard
                let pathStr = String (data: data, encoding: String.Encoding.utf8),
                pathStr.isEmpty == false
                else { return nil }
            
            for component in pathStr.split(separator: "/") {
                if component.contains("textbundle") {
                    return String(component).replacingOccurrences(of: ".textbundle", with: "")
                }
            }
            
            return nil
        }

        
        for path in paths {
            guard let bundleName = try textbundleNameThatContainsImage(named: path.lastComponent) else { continue }
            let root = PathHelper.publicFolderPath
            let bundlePath = root
                + Path(String(PathHelper.makeBundleAssetsPath(filename: bundleName, location: .posts)
                .dropFirst()))
            let newFilepath = bundlePath + Path("assets") + Path(path.lastComponent)
            try path.move(newFilepath)
        }
    }
    
    private static func relinkImagesInText(_ markdown: Markdown, urlPath: String) -> String {
        var output = markdown
        let matches = findImagesInText(markdown)
        for match in matches {
            let range = match.range
            let fullImageMarkdown = NSString(string: markdown).substring(with: range)
            // Formatted like ![](/path/to/image.jpg)
            guard let filepath = fullImageMarkdown.split(separator: "(")
                .last?
                .replacingOccurrences(of: ")", with: ""),
                filepath.contains("http") == false
                else { continue }
            // we should have a link like `assets/image.jpg`
            // it needs to become `/_posts/2018-04-09-hawaii-trip.textbundle/assets/image.jpg`
            let newImagePath = "\(urlPath)/\(filepath)"
            output = output.replacingOccurrences(of: filepath, with: newImagePath)
        }
        
        return output
    }
}
