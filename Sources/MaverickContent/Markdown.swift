import Leaf
import LeafKit
import Markdown

public enum MaverickMarkdownError: Error, Equatable {
    case invalidAssetSource(String)
}

public enum MaverickMarkdown {
    public static func render(_ markdown: String) throws -> String {
        try render(markdown, assetURL: { _ in nil })
    }

    public static func render(
        _ markdown: String,
        assetURL: @escaping (String) throws -> String?,
        linkURL: ((String) throws -> String?)? = nil
    ) throws -> String {
        var rewriter = AssetLinkRewriter(assetURL: assetURL, linkURL: linkURL)
        let document = Document(parsing: markdown)
        guard let rewritten = rewriter.visit(document) else {
            throw MaverickMarkdownError.invalidAssetSource(markdown)
        }
        if let invalidSource = rewriter.invalidSource {
            throw MaverickMarkdownError.invalidAssetSource(invalidSource)
        }
        return HTMLFormatter.format(rewritten)
    }

    private struct AssetLinkRewriter: MarkupRewriter {
        let assetURL: (String) throws -> String?
        let linkURL: ((String) throws -> String?)?
        var invalidSource: String?

        mutating func visitImage(_ image: Image) -> Markup? {
            var image = image
            do {
                if let source = image.source, let rewritten = try assetURL(source) {
                    image.source = rewritten
                }
            } catch {
                invalidSource = image.source
            }
            return defaultVisit(image)
        }

        mutating func visitLink(_ link: Link) -> Markup? {
            var link = link
            do {
                if let destination = link.destination,
                   let rewritten = try assetURL(destination) ?? linkURL?(destination) {
                    link.destination = rewritten
                }
            } catch {
                invalidSource = link.destination
            }
            return defaultVisit(link)
        }
    }
}

/// Registers the same Markdown syntax used by Maverick content as a Leaf tag.
/// The result is intentionally unescaped because it is already HTML.
public struct MaverickMarkdownTag: UnsafeUnescapedLeafTag, Sendable {
    public init() {}

    public func render(_ ctx: LeafContext) throws -> LeafData {
        guard let markdown = ctx.parameters.first?.string else {
            throw LeafError(.unknownError("#markdown(): expected a Markdown string"))
        }
        return LeafData.string(try MaverickMarkdown.render(markdown))
    }
}
