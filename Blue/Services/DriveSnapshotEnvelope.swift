import CryptoKit
import Foundation

/// Visible file contains ciphertext and the non-secret ID of its account-protected recovery key.
struct DriveSnapshotEnvelope: Codable, Sendable {
    static let magic = Data("BLUEBACKUP\u{0}\u{2}".utf8)
    let version: Int
    let keyID: String
    let ciphertext: Data

    static func seal(_ snapshot: AppBackupSnapshot, keyID: String, key: Data) throws -> Data {
        guard key.count == 32 else { throw BlueError.invalidValue }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ciphertext = try EncryptedBackup.seal(encoder.encode(snapshot), key: SymmetricKey(data: key))
        return magic + (try encoder.encode(Self(version: 1, keyID: keyID, ciphertext: ciphertext)))
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 50_000_000, data.starts(with: magic) else { throw BlueError.invalidValue }
        let value = try JSONDecoder().decode(Self.self, from: data.dropFirst(magic.count))
        guard value.version == 1, !value.keyID.isEmpty else { throw BlueError.invalidValue }
        return value
    }
    func open(key: Data) throws -> AppBackupSnapshot {
        guard key.count == 32 else { throw BlueError.invalidValue }
        let plain = try EncryptedBackup.open(ciphertext, key: SymmetricKey(data: key))
        let snapshot = try JSONDecoder().decode(AppBackupSnapshot.self, from: plain)
        guard snapshot.version == AppBackupSnapshot.currentVersion else { throw BlueError.unsupported }
        return snapshot
    }
}
