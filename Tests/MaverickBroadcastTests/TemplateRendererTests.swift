import Foundation
import MaverickBroadcast
import MaverickModels
import XCTest

final class TemplateRendererTests: XCTestCase {
    func testMultilineTemplateRendersValues() throws {
        let post = PostPayload(
            url: URL(string: "https://example.com/post")!,
            title: "A Post",
            description: "A useful description.",
            excerpt: "Longer content",
            tags: ["swift"],
            publicationDate: Date(),
            isMicroblog: false,
            siteTitle: "Example"
        )
        let provider = BroadcastingProviderConfig(
            id: "bluesky",
            type: .bluesky,
            postTemplate: """
            {{title}}

            {{description}}

            {{url}}
            """
        )

        let rendered = try TemplateRenderer().render(post: post, provider: provider, characterLimit: 300)

        XCTAssertEqual(rendered, "A Post\n\nA useful description.\n\nhttps://example.com/post")
    }

    func testDescriptionIsShortenedBeforeImmutableFields() throws {
        let post = PostPayload(
            url: URL(string: "https://example.com/post")!,
            title: "Title",
            description: String(repeating: "x", count: 100),
            excerpt: "",
            tags: [],
            publicationDate: Date(),
            isMicroblog: false,
            siteTitle: "Example"
        )
        let provider = BroadcastingProviderConfig(
            id: "short",
            type: .mastodon,
            postTemplate: "{{title}} {{description}} {{url}}"
        )

        let rendered = try TemplateRenderer().render(post: post, provider: provider, characterLimit: 45)

        XCTAssertLessThanOrEqual(rendered.count, 45)
        XCTAssertTrue(rendered.hasSuffix("https://example.com/post"))
        XCTAssertTrue(rendered.contains("…"))
    }
}
