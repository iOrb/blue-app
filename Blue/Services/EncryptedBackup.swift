import CryptoKit
import Foundation

/// Authenticated, versioned container. Key management is deliberately separate from the file.
enum EncryptedBackup {
    private static let magic = Data("BLUEBACKUP\u{0}\u{1}".utf8)

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: magic)
        guard let combined = sealed.combined else { throw BlueError.saveFailed }
        return magic + combined
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> Data {
        guard data.starts(with: magic) else { throw BlueError.invalidValue }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
        return try AES.GCM.open(box, using: key, authenticating: magic)
    }
}
