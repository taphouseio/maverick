import Crypto
import Foundation

struct SnapshotCipher: Sendable {
    private let keyBytes: [UInt8]

    init(secret: String) {
        if let decoded = Data(base64Encoded: secret), decoded.count == 32 {
            keyBytes = Array(decoded)
        } else {
            keyBytes = Array(SHA256.hash(data: Data(secret.utf8)))
        }
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        let key = SymmetricKey(data: keyBytes)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw R2StoreError.invalidSnapshot("Unable to create combined encrypted snapshot")
        }
        return combined
    }

    func decrypt(_ encrypted: Data) throws -> Data {
        let key = SymmetricKey(data: keyBytes)
        let box = try AES.GCM.SealedBox(combined: encrypted)
        return try AES.GCM.open(box, using: key)
    }

    static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
