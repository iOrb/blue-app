import Foundation
import Testing

@testable import Blue

struct GoogleDriveBackupTests {
    @Test func refusesPlaintextAndInvalidFolderWithoutNetwork() async {
        let drive = GoogleDriveBackupClient()
        await #expect(throws: GoogleDriveBackupClient.Failure.self) {
            try await drive.upload(encrypted: Data("private note".utf8), folderID: "folder", token: "token")
        }
        await #expect(throws: GoogleDriveBackupClient.Failure.self) {
            try await drive.upload(
                encrypted: Data("BLUEBACKUP\u{0}\u{1}ciphertext".utf8), folderID: "../folder", token: "token")
        }
    }
}
