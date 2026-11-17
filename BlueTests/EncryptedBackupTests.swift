import CryptoKit
import Foundation
import Testing

@testable import Blue

struct EncryptedBackupTests {
    @Test func authenticatedBackupHidesAndRecoversData() throws {
        let key = SymmetricKey(size: .bits256)
        let original = Data("A private Blue note".utf8)
        let first = try EncryptedBackup.seal(original, key: key)
        let second = try EncryptedBackup.seal(original, key: key)
        #expect(first != second)
        #expect(first.range(of: original) == nil)
        #expect(try EncryptedBackup.open(first, key: key) == original)
        #expect(throws: (any Error).self) {
            try EncryptedBackup.open(first, key: SymmetricKey(size: .bits256))
        }
        var corrupted = first
        corrupted[corrupted.count - 1] ^= 1
        #expect(throws: (any Error).self) { try EncryptedBackup.open(corrupted, key: key) }
    }
}

@MainActor
struct AppBackupSnapshotTests {
    @Test func snapshotIncludesPreferencesAndCredentialsOnlyInsideEncryptedPayload() throws {
        let suite = "blue.snapshot.test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("es", forKey: "blue.language")
        defaults.set("dark", forKey: "blue.appearance")
        defaults.set("gpt-live-1", forKey: "blue.assistant.voice.openai")
        var library = LibraryState()
        library.notes = [Note(title: .user("Private"), markdown: .user("Content"))]
        library.events = [CalendarEvent(title: "Event", date: .now, weekdays: [2, 6])]
        let snapshot = AppBackupSnapshot.capture(library: library, defaults: defaults) {
            $0 == .openai ? "example-secret-not-a-real-key" : nil
        }
        #expect(snapshot.preferences["blue.language"] == "es")
        #expect(snapshot.preferences["blue.assistant.voice.openai"] == "gpt-live-1")
        #expect(snapshot.credentials["openai"] == "example-secret-not-a-real-key")
        let key = SymmetricKey(size: .bits256)
        let ciphertext = try EncryptedBackup.seal(JSONEncoder().encode(snapshot), key: key)
        #expect(ciphertext.range(of: Data("example-secret-not-a-real-key".utf8)) == nil)
        let decoded = try JSONDecoder().decode(AppBackupSnapshot.self, from: EncryptedBackup.open(ciphertext, key: key))
        #expect(decoded == snapshot)
    }
}
