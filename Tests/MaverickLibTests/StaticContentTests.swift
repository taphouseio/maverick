import Foundation
import MaverickContent
import MaverickModels
import XCTest

final class StaticContentTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("maverick-pages-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testPageRendersAndRewritesBundleAssets() async throws {
        try writeBundle(
            at: "privacy",
            metadata: StaticPageMetadata(title: "Privacy", description: "Our privacy policy"),
            markdown: "# Privacy\n\n![Logo](assets/logo.png)\n\n[Terms](terms)"
        )
        try writeBundle(at: "terms", metadata: StaticPageMetadata(title: "Terms"), markdown: "# Terms")
        try Data("image".utf8).write(to: bundleURL(for: "privacy").appendingPathComponent("assets/logo.png"))

        let store = try makeStore()
        let target = try await store.renderTarget(for: "privacy")

        XCTAssertEqual(target.template, "legal")
        XCTAssertEqual(target.context.title, "Privacy")
        XCTAssertTrue(target.context.contentHTML.contains("_asset"))
        XCTAssertTrue(target.context.contentHTML.contains("page=privacy"))
        XCTAssertTrue(target.context.contentHTML.contains("href=\"/terms\""))
    }

    func testSingleBundleConfigurationRendersAtItsMountedRoute() async throws {
        let bundle = bundleURL(for: "privacy")
        try writeBundle(at: "privacy", metadata: BundleContentMetadata(title: "Privacy"), markdown: "Privacy")
        let configuration = try BundleContentConfiguration(
            bundleURL: bundle,
            routePath: ["privacy"],
            pageTemplate: "legal"
        )
        let store = BundleContentStore(configuration: configuration)

        let target = try await store.renderTarget(for: "")
        XCTAssertEqual(target.context.title, "Privacy")
    }

    func testInvalidUpdateKeepsLastValidSnapshot() async throws {
        try writeBundle(at: "privacy", metadata: StaticPageMetadata(title: "Privacy"), markdown: "Original")
        let store = try makeStore()
        _ = try await store.renderTarget(for: "privacy")

        let broken = bundleURL(for: "broken")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: broken.appendingPathComponent("info.json"))
        try Data("Broken".utf8).write(to: broken.appendingPathComponent("text.md"))

        let target = try await store.renderTarget(for: "privacy")
        XCTAssertEqual(target.context.title, "Privacy")
    }

    func testDraftsAreNotPublished() async throws {
        try writeBundle(at: "draft", metadata: StaticPageMetadata(title: "Draft", draft: true), markdown: "Draft")
        let store = try makeStore()

        do {
            _ = try await store.renderTarget(for: "draft")
            XCTFail("Expected draft to be hidden")
        } catch let error as StaticContentError {
            XCTAssertEqual(error, .notFound("draft"))
        }
    }

    func testAssetTraversalIsRejected() async throws {
        try writeBundle(at: "privacy", metadata: StaticPageMetadata(title: "Privacy"), markdown: "Privacy")
        let store = try makeStore()

        do {
            _ = try await store.asset(pagePath: "privacy", assetPath: "../secret.txt")
            XCTFail("Expected traversal to be rejected")
        } catch let error as StaticContentError {
            XCTAssertEqual(error, .invalidAsset("../secret.txt"))
        }
    }

    private func makeStore() throws -> StaticContentStore {
        let configuration = try StaticContentConfiguration(contentRoot: root, pageTemplate: "legal")
        return StaticContentStore(configuration: configuration)
    }

    private func writeBundle(at relativePath: String, metadata: StaticPageMetadata, markdown: String) throws {
        let bundle = bundleURL(for: relativePath)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try BundleInfo.defaultWithStaticPageMetadata(metadata).toData().write(to: bundle.appendingPathComponent("info.json"))
        try Data(markdown.utf8).write(to: bundle.appendingPathComponent("text.md"))
    }

    private func bundleURL(for relativePath: String) -> URL {
        let components = relativePath.split(separator: "/").map(String.init)
        let parent = components.dropLast().reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
        return parent.appendingPathComponent((components.last ?? "index") + ".textbundle", isDirectory: true)
    }
}
