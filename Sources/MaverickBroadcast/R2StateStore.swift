import AWSS3
import Crypto
import Foundation
import MaverickModels
import Smithy
import SmithyIdentity

public enum R2StoreError: Error, LocalizedError, Sendable {
    case unavailable(String)
    case invalidSnapshot(String)
    case unsupportedConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message), .invalidSnapshot(let message), .unsupportedConfiguration(let message):
            return message
        }
    }
}

public actor R2StateStore: StateStore {
    private struct LatestPointer: Codable, Sendable {
        let snapshot: SnapshotDescriptor
    }

    private let configuration: BroadcastingStateConfig
    private let keyPrefix: String
    private let client: R2Client
    private let cipher: SnapshotCipher
    private let cacheURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configuration: BroadcastingStateConfig, secrets: any SecretResolver) throws {
        guard configuration.type == "r2" else {
            throw R2StoreError.unsupportedConfiguration("Unsupported state store: \(configuration.type)")
        }
        guard let r2 = configuration.r2 else {
            throw R2StoreError.unsupportedConfiguration("R2 state requires an r2 configuration block")
        }
        let accountID = try secrets.resolve(r2.accountIDSecret)
        let accessKeyID = try secrets.resolve(r2.accessKeyIDSecret)
        let secretAccessKey = try secrets.resolve(r2.secretAccessKeySecret)
        let encryptionSecret = try secrets.resolve(configuration.encryptionKeySecret)

        self.configuration = configuration
        self.keyPrefix = r2.keyPrefix
        self.client = try R2Client(
            accountID: accountID,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            bucket: r2.bucket
        )
        self.cipher = SnapshotCipher(secret: encryptionSecret)
        self.cacheURL = URL(
            fileURLWithPath: configuration.localCachePath ?? "/app/Data/broadcast-state.json.enc",
            isDirectory: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() async throws -> StoreLoadResult {
        do {
            guard let pointerData = try await client.getObject(key: latestKey) else {
                let existingSnapshots = try await client.listObjects(prefix: normalizedPrefix + "/snapshots/")
                guard existingSnapshots.isEmpty else {
                    throw R2StoreError.invalidSnapshot(
                        "R2 latest.json is missing even though encrypted snapshots exist; restore a snapshot explicitly"
                    )
                }
                return .uninitialized
            }
            let pointer = try decoder.decode(LatestPointer.self, from: pointerData)
            if let cached = try? Data(contentsOf: cacheURL),
               SnapshotCipher.checksum(cached) == pointer.snapshot.checksum,
               let cachedLedger = try? decode(cached, expecting: pointer.snapshot) {
                return .loaded(cachedLedger, pointer.snapshot)
            }
            let ledger = try await restore(pointer.snapshot)
            return .loaded(ledger, pointer.snapshot)
        } catch {
            throw R2StoreError.unavailable("Unable to restore authoritative R2 state: \(error.localizedDescription)")
        }
    }

    public func commit(_ ledger: Ledger) async throws -> SnapshotDescriptor {
        let plaintext = try encoder.encode(ledger)
        let encrypted = try cipher.encrypt(plaintext)
        let checksum = SnapshotCipher.checksum(encrypted)
        let snapshot = SnapshotDescriptor(
            revision: ledger.revision,
            key: snapshotKey(revision: ledger.revision, checksum: checksum),
            checksum: checksum,
            createdAt: Date()
        )

        try await client.putObject(key: snapshot.key, data: encrypted, contentType: "application/octet-stream")
        let pointer = try encoder.encode(LatestPointer(snapshot: snapshot))
        try await client.putObject(key: latestKey, data: pointer, contentType: "application/json")
        updateLocalCacheBestEffort(encrypted)
        return snapshot
    }

    public func snapshots() async throws -> [SnapshotDescriptor] {
        let keys = try await client.listObjects(prefix: normalizedPrefix + "/snapshots/")
        return keys.compactMap(Self.descriptor(from:)).sorted { $0.revision > $1.revision }
    }

    public func restore(_ snapshot: SnapshotDescriptor) async throws -> Ledger {
        guard let data = try await client.getObject(key: snapshot.key) else {
            throw R2StoreError.invalidSnapshot("R2 snapshot is missing: \(snapshot.key)")
        }
        guard SnapshotCipher.checksum(data) == snapshot.checksum else {
            throw R2StoreError.invalidSnapshot("Checksum mismatch for R2 snapshot revision \(snapshot.revision)")
        }
        let ledger = try decode(data, expecting: snapshot)
        updateLocalCacheBestEffort(data)
        return ledger
    }

    private func decode(_ encrypted: Data, expecting snapshot: SnapshotDescriptor) throws -> Ledger {
        let plaintext = try cipher.decrypt(encrypted)
        let ledger = try decoder.decode(Ledger.self, from: plaintext)
        guard ledger.revision == snapshot.revision else {
            throw R2StoreError.invalidSnapshot("Revision mismatch in \(snapshot.key)")
        }
        return ledger
    }

    private var normalizedPrefix: String {
        keyPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var latestKey: String { normalizedPrefix + "/latest.json" }

    private func snapshotKey(revision: UInt64, checksum: String) -> String {
        let formatted = String(format: "%020llu", revision)
        return normalizedPrefix + "/snapshots/\(formatted)-\(checksum).json.enc"
    }

    private static func descriptor(from key: String) -> SnapshotDescriptor? {
        guard let filename = key.split(separator: "/").last else { return nil }
        let parts = filename.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let revision = UInt64(parts[0]) else { return nil }
        let checksum = parts[1].replacingOccurrences(of: ".json.enc", with: "")
        guard checksum.count == 64 else { return nil }
        return SnapshotDescriptor(revision: revision, key: key, checksum: checksum, createdAt: .distantPast)
    }

    private func updateLocalCache(_ data: Data) throws {
        let directory = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(cacheURL.lastPathComponent).\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            _ = try FileManager.default.replaceItemAt(cacheURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: cacheURL)
        }
    }

    private func updateLocalCacheBestEffort(_ data: Data) {
        // R2 is authoritative. A cache refresh must never turn an already-successful
        // R2 commit or restore into a reported failure.
        try? updateLocalCache(data)
    }
}

private struct R2Client: Sendable {
    private let client: S3Client
    private let bucket: String

    init(accountID: String, accessKeyID: String, secretAccessKey: String, bucket: String) throws {
        let identity = AWSCredentialIdentity(accessKey: accessKeyID, secret: secretAccessKey)
        let resolver = StaticAWSCredentialIdentityResolver(identity)
        let configuration = try S3Client.S3ClientConfig(
            awsCredentialIdentityResolver: resolver,
            region: "auto",
            signingRegion: "auto",
            forcePathStyle: true,
            endpoint: "https://\(accountID).r2.cloudflarestorage.com"
        )
        self.client = S3Client(config: configuration)
        self.bucket = bucket
    }

    func getObject(key: String) async throws -> Data? {
        do {
            let output = try await client.getObject(input: GetObjectInput(bucket: bucket, key: key))
            return try await output.body?.readData() ?? Data()
        } catch is NoSuchKey {
            return nil
        }
    }

    func putObject(key: String, data: Data, contentType: String) async throws {
        _ = try await client.putObject(input: PutObjectInput(
            body: .data(data),
            bucket: bucket,
            contentLength: data.count,
            contentType: contentType,
            key: key
        ))
    }

    func listObjects(prefix: String) async throws -> [String] {
        var keys: [String] = []
        var continuationToken: String?
        repeat {
            let output = try await client.listObjectsV2(input: ListObjectsV2Input(
                bucket: bucket,
                continuationToken: continuationToken,
                prefix: prefix
            ))
            keys.append(contentsOf: output.contents?.compactMap(\.key) ?? [])
            continuationToken = output.isTruncated == true ? output.nextContinuationToken : nil
        } while continuationToken != nil
        return keys
    }
}
