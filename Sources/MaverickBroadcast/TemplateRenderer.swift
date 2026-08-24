import Crypto
import Foundation
import MaverickModels

public struct TemplateRenderer: Sendable {
    public init() {}

    public func render(
        post: PostPayload,
        provider: BroadcastingProviderConfig,
        characterLimit: Int
    ) throws -> String {
        let override = post.metadata?.providers[provider.id]
        if post.metadata?.skip == true || override?.skip == true {
            throw ProviderFailure.validation("Post is configured to skip \(provider.id)")
        }

        let template = override?.template ?? provider.postTemplate
        var values = values(for: post)
        var rendered = substitute(template, values: values)
        if rendered.count <= characterLimit { return rendered }

        for flexibleKey in ["description", "excerpt"] {
            guard let original = values[flexibleKey], !original.isEmpty else { continue }
            var low = 0
            var high = original.count
            var best: String?
            while low <= high {
                let middle = (low + high) / 2
                values[flexibleKey] = shortened(original, maximum: middle)
                let candidate = substitute(template, values: values)
                if candidate.count <= characterLimit {
                    best = candidate
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            if let best { return best }
            values[flexibleKey] = ""
            rendered = substitute(template, values: values)
        }

        throw ProviderFailure.validation(
            "Rendered post is \(rendered.count) characters; \(provider.id) allows \(characterLimit)"
        )
    }

    public func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func values(for post: PostPayload) -> [String: String] {
        [
            "title": post.title ?? "",
            "description": post.description,
            "excerpt": post.excerpt,
            "url": post.url.absoluteString,
            "siteTitle": post.siteTitle,
            "tags": post.tags.joined(separator: " "),
        ]
    }

    private func substitute(_ template: String, values: [String: String]) -> String {
        var output = template
        for (key, value) in values {
            output = output.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return normalizeBlankLines(output)
    }

    private func normalizeBlankLines(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty, output.last?.isEmpty == true { continue }
            output.append(trimmed)
        }
        while output.first?.isEmpty == true { output.removeFirst() }
        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n")
    }

    private func shortened(_ text: String, maximum: Int) -> String {
        guard text.count > maximum else { return text }
        guard maximum > 1 else { return maximum == 1 ? "…" : "" }
        let prefix = String(text.prefix(maximum - 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }
}
