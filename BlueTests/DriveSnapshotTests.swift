import CryptoKit
import Foundation
import Testing

@testable import Blue

struct DriveSnapshotTests {
    @Test func anotherDeviceCanReadTheFileWithTheAccountRecoveryKey() throws {
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        var state = LibraryState()
        state.notes = [Note(title: .user("Private fixture"), markdown: .user("Saved on the phone"))]
        state.events = [CalendarEvent(title: "Coffee", date: .now, weekdays: [2, 5])]
        let snapshot = AppBackupSnapshot(
            library: state, preferences: ["blue.language": "es"], credentials: ["openai": "example-secret"])
        let uploadedFile = try DriveSnapshotEnvelope.seal(snapshot, keyID: "accountKeyID", key: key)
        #expect(uploadedFile.range(of: Data("Saved on the phone".utf8)) == nil)
        #expect(uploadedFile.range(of: Data("example-secret".utf8)) == nil)
        let otherDevice = try DriveSnapshotEnvelope.decode(Data(uploadedFile))
        #expect(otherDevice.keyID == "accountKeyID")
        #expect(try otherDevice.open(key: key) == snapshot)
        let wrongKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        #expect(throws: (any Error).self) { try otherDevice.open(key: wrongKey) }
    }
}
