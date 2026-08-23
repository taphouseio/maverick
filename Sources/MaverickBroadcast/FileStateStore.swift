import Foundation
import MaverickModels

/// An encrypted authoritative ledger for local development and tests.
/// Production runtimes reject this store so R2 remains authoritative in deployment.
public actor FileStateStore: StateStore {
    private struct LatestPointer: Codable, Sendable {
        let snapshot: SnapshotDescriptor
    }

    private let rootURL: URL
    private let snapshotsURL: URL
    private let latestURL: URL
    private let cipher: SnapshotCipher
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configuration: BroadcastingStateConfig, secrets: any SecretResolver) throws {
        guard configuration.type == "local" else {
            throw R2StoreError.unsupportedConfiguration("Unsupported local state store: \(configuration.type)")
        }
        guard let path = configuration.path, !path.isEmpty else {
            throw R2StoreError.unsupportedConfiguration("Local state requires path")
        }
        rootURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        snapshotsURL = rootURL.appendingPathComponent("snapshots", isDirectory: true)
        latestURL = rootURL.appendingPathComponent("latest.json", isDirectory: false)
        cipher = SnapshotCipher(secret: try secrets.resolve(configuration.encryptionKeySecret))

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
            guard FileManager.default.fileExists(atPath: latestURL.path) else {
                guard try snapshotFiles().isEmpty else {
                    throw R2StoreError.invalidSnapshot(
                        "Local latest.json is missing even though encrypted snapshots exist; restore one explicitly"
                    )
                }
                return .uninitialized
            }
            let pointer = try decoder.decode(LatestPointer.self, from: Data(contentsOf: latestURL))
            return .loaded(try read(pointer.snapshot), pointer.snapshot)
        } catch {
            throw R2StoreError.unavailable("Unable to restore authoritative local state: \(error.localizedDescription)")
        }
    }

    public func commit(_ ledger: Ledger) async throws -> SnapshotDescriptor {
        try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        let encrypted = try cipher.encrypt(encoder.encode(ledger))
        let checksum = SnapshotCipher.checksum(encrypted)
        let filename = "\(String(format: "%020llu", ledger.revision))-\(checksum).json.enc"
        let snapshot = SnapshotDescriptor(
            revision: ledger.revision,
            key: "snapshots/\(filename)",
            checksum: checksum,
            createdAt: Date()
        )
        let destination = snapshotsURL.appendingPathComponent(filename, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw R2StoreError.invalidSnapshot("Refusing to overwrite immutable snapshot \(snapshot.key)")
        }
        try encrypted.write(to: destination, options: .atomic)
        try encoder.encode(LatestPointer(snapshot: snapshot)).write(to: latestURL, options: .atomic)
        return snapshot
    }

    public func snapshots() async throws -> [SnapshotDescriptor] {
        try snapshotFiles().compactMap(descriptor(from:)).sorted { $0.revision > $1.revision }
    }

    public func restore(_ snapshot: SnapshotDescriptor) async throws -> Ledger {
        try read(snapshot)
    }

    private func read(_ snapshot: SnapshotDescriptor) throws -> Ledger {
        let url = try snapshotURL(for: snapshot)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw R2StoreError.invalidSnapshot("Local snapshot is missing: \(snapshot.key)")
        }
        let encrypted = try Data(contentsOf: url)
        guard SnapshotCipher.checksum(encrypted) == snapshot.checksum else {
            throw R2StoreError.invalidSnapshot("Checksum mismatch for local revision \(snapshot.revision)")
        }
        let ledger = try decoder.decode(Ledger.self, from: cipher.decrypt(encrypted))
        guard ledger.revision == snapshot.revision else {
            throw R2StoreError.invalidSnapshot("Revision mismatch in \(snapshot.key)")
        }
        return ledger
    }

    private func snapshotFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: snapshotsURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: snapshotsURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "enc" }
    }

    private func descriptor(from url: URL) -> SnapshotDescriptor? {
        let suffix = ".json.enc"
        guard url.lastPathComponent.hasSuffix(suffix) else { return nil }
        let stem = String(url.lastPathComponent.dropLast(suffix.count))
        let parts = stem.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let revision = UInt64(parts[0]), parts[1].count == 64 else { return nil }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return SnapshotDescriptor(
            revision: revision,
            key: "snapshots/\(url.lastPathComponent)",
            checksum: parts[1],
            createdAt: values?.creationDate ?? values?.contentModificationDate ?? .distantPast
        )
    }

    private func snapshotURL(for snapshot: SnapshotDescriptor) throws -> URL {
        let components = snapshot.key.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, components[0] == "snapshots",
              !components[1].isEmpty, components[1] != ".", components[1] != ".." else {
            throw R2StoreError.invalidSnapshot("Invalid local snapshot key: \(snapshot.key)")
        }
        return snapshotsURL.appendingPathComponent(String(components[1]), isDirectory: false)
    }
}
