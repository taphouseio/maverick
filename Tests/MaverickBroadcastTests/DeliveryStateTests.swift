import Foundation
@testable import MaverickBroadcast
import XCTest

final class DeliveryStateTests: XCTestCase {
    func testMissingGenerationDecodesAsInitialGeneration() throws {
        let json = """
        {
          "status": "delivered",
          "attemptCount": 1,
          "createdAt": 0,
          "updatedAt": 0
        }
        """

        let delivery = try JSONDecoder().decode(DeliveryState.self, from: Data(json.utf8))

        XCTAssertEqual(delivery.generation, 0)
    }
}
