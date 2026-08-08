import Foundation
import MaverickContent
import MaverickModels
import XCTest

final class SupportContentTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("maverick-support-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testNestedContentRendersAndRewritesBundleAssets() async throws {
        try writeBundle(
            at: "index",
            metadata: SupportArticleMetadata(title: "Arborist Help"),
            markdown: "Start here."
        )
        try writeBundle(
            at: "getting-started/index",
            metadata: SupportArticleMetadata(title: "Getting Started", order: 10),
            markdown: "Choose a guide."
        )
        try writeBundle(
            at: "getting-started/install",
            metadata: SupportArticleMetadata(title: "Install Arborist", order: 10),
            markdown: "![Screenshot](assets/screenshot.png)\n\n[Download](assets/guide.pdf)"
        )

        let articleURL = bundleURL(for: "getting-started/install")
            .appendingPathComponent("assets/screenshot.png")
        try Data("image".utf8).write(to: articleURL)

        let store = try makeStore()
        let target = try await store.renderTarget(for: "getting-started/install")

        XCTAssertEqual(target.template, "article")
        XCTAssertEqual(target.context.article.title, "Install Arborist")
        XCTAssertTrue(target.context.article.contentHTML.contains("_asset"))
        XCTAssertTrue(target.context.article.contentHTML.contains("guide.pdf"))
        XCTAssertEqual(target.context.breadcrumbs.map(\.title), ["Help", "Getting Started", "Install Arborist"])
    }

    func testInvalidUpdateKeepsLastValidSnapshot() async throws {
        try writeBundle(at: "index", metadata: SupportArticleMetadata(title: "Help"), markdown: "Original")
        let store = try makeStore()
        _ = try await store.renderTarget(for: "")

        try writeBundle(at: "getting-started", metadata: SupportArticleMetadata(title: "First"), markdown: "Valid")
        try writeBundle(at: "getting-started/index", metadata: SupportArticleMetadata(title: "Duplicate"), markdown: "Invalid")

        let target = try await store.renderTarget(for: "")
        XCTAssertEqual(target.context.article.title, "Help")
    }

    func testDraftsAreNotPublished() async throws {
        try writeBundle(at: "index", metadata: SupportArticleMetadata(title: "Help"), markdown: "Help")
        try writeBundle(
            at: "draft",
            metadata: SupportArticleMetadata(title: "Draft", draft: true),
            markdown: "Draft"
        )

        let store = try makeStore()
        await XCTAssertThrowsErrorAsync(try await store.renderTarget(for: "draft"))
    }

    func testAssetTraversalIsRejected() async throws {
        try writeBundle(at: "index", metadata: SupportArticleMetadata(title: "Help"), markdown: "Help")
        let store = try makeStore()

        do {
            _ = try await store.asset(bundlePath: "", assetPath: "../secret.txt")
            XCTFail("Expected traversal to be rejected")
        } catch let error as SupportContentError {
            XCTAssertEqual(error, .invalidAsset("../secret.txt"))
        }
    }

    private func makeStore() throws -> SupportContentStore {
        let configuration = try SupportContentConfiguration(
            contentRoot: root,
            routePath: ["arborist", "help"],
            indexTemplate: "index",
            sectionTemplate: "section",
            articleTemplate: "article"
        )
        return SupportContentStore(configuration: configuration)
    }

    private func writeBundle(at relativePath: String, metadata: SupportArticleMetadata, markdown: String) throws {
        let bundle = bundleURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try BundleInfo.defaultWithSupportMetadata(metadata).toData().write(
            to: bundle.appendingPathComponent("info.json")
        )
        try Data(markdown.utf8).write(to: bundle.appendingPathComponent("text.md"))
    }

    private func bundleURL(for relativePath: String) -> URL {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let last = components.last else { return root.appendingPathComponent("index.textbundle") }
        let parent = components.dropLast().reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
        return parent.appendingPathComponent(last + ".textbundle", isDirectory: true)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
