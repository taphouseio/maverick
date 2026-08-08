@testable import MaverickLib
import MaverickModels
import PathKit
import TextBundleify
import XCTest

private let sampleFileText = """
---
filename: 2019-01-21-test-blog-post
layout: post
title: Test post for unit testing purposes only
date: '2019-01-21 21:46:47'
---
This is a test blog post.
"""

final class FileGeneratorTests : XCTestCase {
    static let allTests = [
        ("testFeedsAreGenerated", testFeedsAreGenerated),
        ("testGeneratedFeedsHaveExactSameContentBetweenGenerations", testGeneratedFeedsHaveExactSameContentBetweenGenerations),
        ("testAddingANewItemChangesTheFeed", testAddingANewItemChangesTheFeed),
    ]

    var testFilename: String {
        let calendar = Calendar.current
        let date = Date()
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        let slug = "test-post"
        let path = PostPath(year: year, month: month, day: day, slug: slug)
        return path.asFilename
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try PathHelper.publicFolderPath.mkpath()
        try PathHelper.postFolderPath.mkpath()

        let testMdPath = PathHelper.postFolderPath + Path("\(testFilename).md")
        if testMdPath.exists {
            try? testMdPath.delete()
        }

        let testFilePath = PathHelper.postFolderPath + Path("\(testFilename).textbundle")
        if testFilePath.exists {
            try? testFilePath.delete()
        }
    }

    override func tearDown() {
        super.tearDown()
        let testFilePath = PathHelper.postFolderPath + Path("\(testFilename).textbundle")
        if testFilePath.exists {
            try? testFilePath.delete()
        }
    }

    func testFeedsAreGenerated() throws {
        try FeedOutput.makeAllTheFeeds()
        let publicPath = PathHelper.publicFolderPath

        for (generator, textType) in FeedOutput.allOutputsAndGenerators {
            let filename = generator.outputFileName(forType: textType)
            let feedPath = publicPath + Path(filename)
            XCTAssertTrue(feedPath.exists)
        }
    }

    func testGeneratedFeedsHaveExactSameContentBetweenGenerations() throws {
        let config = try SiteConfigController.fetchSite()
        let posts = try FeedOutput.postsToGenerate(for: .fullText)

        for (generator, textType) in FeedOutput.allOutputsAndGenerators {
            let firstFeed = try generator.makeFeed(from: posts, for: config, goingTo: textType)
            let secondFeed = try generator.makeFeed(from: posts, for: config, goingTo: textType)

            XCTAssertEqual(firstFeed, secondFeed)
        }
    }

    func testGeneratedFeedsWithoutChangesDontReportChanges() throws {
        try FeedOutput.makeAllTheFeeds() // seeding the files
        let first = try FeedOutput.makeAllTheFeeds()
        let second = try FeedOutput.makeAllTheFeeds()

        XCTAssertFalse(first)
        XCTAssertEqual(first, second)
    }

    func testAddingANewItemChangesTheFeed() throws {
        try FeedOutput.makeAllTheFeeds()

        let path = PathHelper.postFolderPath + Path("\(testFilename).md")
        try path.write(sampleFileText)
        try TextBundleify.start(in: PathHelper.postFolderPath, pathToAssets: nil)

        let changed = try FeedOutput.makeAllTheFeeds()
        XCTAssertTrue(changed)
    }
}
