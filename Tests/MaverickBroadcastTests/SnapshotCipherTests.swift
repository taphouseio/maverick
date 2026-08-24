import Foundation
@testable import MaverickBroadcast
import XCTest

final class SnapshotCipherTests: XCTestCase {
    func testRoundTripAndTamperDetection() throws {
        let cipher = SnapshotCipher(secret: "a secret stored outside R2")
        let plaintext = Data("ledger".utf8)
        let encrypted = try cipher.encrypt(plaintext)

        XCTAssertNotEqual(encrypted, plaintext)
        XCTAssertEqual(try cipher.decrypt(encrypted), plaintext)
        XCTAssertEqual(SnapshotCipher.checksum(encrypted).count, 64)

        var tampered = encrypted
        tampered[tampered.startIndex] ^= 0xff
        XCTAssertThrowsError(try cipher.decrypt(tampered))
    }
}
