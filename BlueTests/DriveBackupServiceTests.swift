import CryptoKit
import Foundation
import Testing

@testable import Blue

@MainActor private final class BackupAccountFixture: DriveBackupConnection {
    var connected = true
    var hasBackupPermission = true
    var account: String? = "fixture@example.com"
    func accessToken() async throws -> String { "example-token" }
}

private actor BackupCloudFixture: DriveHTTPTransport {
    let key: Data
    private(set) var stored: Data
    private(set) var uploads = 0
    private(set) var calls = 0
    init(snapshot: AppBackupSnapshot, key: Data) throws {
        self.key = key
        stored = try DriveSnapshotEnvelope.seal(snapshot, keyID: "key", key: key)
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        try await Task.sleep(for: .milliseconds(10))
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let data: Data
        if url.path.contains("generateIds") {
            data = Data(#"{"ids":["reserved"]}"#.utf8)
        } else if request.httpMethod == "PATCH" {
            stored = request.httpBody!
            uploads += 1
            data = Data(#"{"id":"existing"}"#.utf8)
        } else if query.contains(where: { $0.name == "q" }) {
            if query.contains(where: { $0.value?.contains("mimeType") == true }) {
                data = Data(#"{"files":[{"id":"folder","appProperties":{"blueRole":"backups"}}]}"#.utf8)
            } else {
                data = Data(#"{"files":[{"id":"existing","appProperties":{"blueInstallation":"deviceA"}}]}"#.utf8)
            }
        } else if query.contains(where: { $0.name == "fields" }), url.path.hasSuffix("/existing") {
            data = Data(#"{"id":"existing","parents":["folder"],"appProperties":{"blueInstallation":"deviceA"}}"#.utf8)
        } else if url.path.hasSuffix("/key") {
            data = key
        } else {
            data = stored
        }
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor struct DriveBackupServiceTests {
    @Test func pendingChangesAreSerializedAndReadableByAnotherClient() async throws {
        let suite = "blue.drive.worker.test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("deviceA", forKey: "blue.drive.installation")
        let original = AppBackupSnapshot(library: LibraryState(), preferences: [:], credentials: [:])
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let cloud = try BackupCloudFixture(snapshot: original, key: key)
        let service = DriveBackupService(defaults: defaults, client: GoogleDriveBackupClient(transport: cloud))
        let account = BackupAccountFixture()
        var first = original
        first.library.notes = [Note(title: .user("First"), markdown: .user("First content"))]
        service.schedule(first, connection: account)
        for _ in 0..<100 {
            if await cloud.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        var latest = first
        latest.library.notes[0].markdown = .user("Latest content")
        service.schedule(latest, connection: account)
        for _ in 0..<150 {
            if await cloud.uploads == 2, !service.saving { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(service.errorKey == nil)
        #expect(service.savedAt != nil)
        #expect(await cloud.uploads == 2)
        #expect(try await service.readSnapshot(fileID: "existing", connection: account) == latest)
        service.schedule(latest, connection: account)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await cloud.uploads == 2)
    }

    @Test func noDataLeavesTheAppWithoutBackupPermission() async throws {
        let snapshot = AppBackupSnapshot(library: LibraryState(), preferences: [:], credentials: [:])
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let cloud = try BackupCloudFixture(snapshot: snapshot, key: key)
        let account = BackupAccountFixture()
        account.hasBackupPermission = false
        let service = DriveBackupService(client: GoogleDriveBackupClient(transport: cloud))
        service.schedule(snapshot, connection: account)
        #expect(await cloud.calls == 0)
        #expect(service.savedAt == nil)
    }
}
