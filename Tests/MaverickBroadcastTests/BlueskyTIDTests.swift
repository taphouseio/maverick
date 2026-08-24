import Foundation
@testable import MaverickBroadcast
import Testing

struct BlueskyTIDTests {
    @Test(
        "Produces a syntactically valid TID",
        arguments: [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1_777_000_000),
            .distantFuture,
        ]
    )
    func validSyntax(publicationDate: Date) {
        let tid = BlueskyTID.make(
            publicationDate: publicationDate,
            generation: 0,
            idempotencyKey: "775c22c78c04325ae6651d59"
        )

        #expect(tid.wholeMatch(of: /^[234567abcdefghij][234567abcdefghijklmnopqrstuvwxyz]{12}$/) != nil)
    }

    @Test("Retries reuse the same TID")
    func stableForSameDeliveryGeneration() {
        let date = Date(timeIntervalSince1970: 1_777_000_000)

        let first = BlueskyTID.make(
            publicationDate: date,
            generation: 0,
            idempotencyKey: "775c22c78c04325ae6651d59"
        )
        let retry = BlueskyTID.make(
            publicationDate: date,
            generation: 0,
            idempotencyKey: "775c22c78c04325ae6651d59"
        )

        #expect(first == retry)
    }

    @Test("Deliberate rebroadcasts use a different TID")
    func changesWithDeliveryGeneration() {
        let date = Date(timeIntervalSince1970: 1_777_000_000)

        let initial = BlueskyTID.make(
            publicationDate: date,
            generation: 0,
            idempotencyKey: "775c22c78c04325ae6651d59"
        )
        let rebroadcast = BlueskyTID.make(
            publicationDate: date,
            generation: 1,
            idempotencyKey: "9fd604bf27f1bc2cc786d60b"
        )

        #expect(initial != rebroadcast)
    }
}
