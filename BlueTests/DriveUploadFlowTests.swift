import CryptoKit
import Foundation
import Testing

@testable import Blue

private actor ScriptedDriveTransport: DriveHTTPTransport {
    private var replies: [(Int, Data)]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, Data)]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw BlueError.saveFailed }
        let (status, bytes) = replies.removeFirst()
        return (bytes, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct DriveUploadFlowTests {
    @Test func updatesOnlyTheInstallationFileAndVerifiesUploadedBytes() async throws {
        let bytes = try EncryptedBackup.seal(Data("Private fixture note".utf8), key: SymmetricKey(size: .bits256))
        let transport = ScriptedDriveTransport([
            (200, Data(#"{"files":[{"id":"existing","appProperties":{"blueInstallation":"deviceA"}}]}"#.utf8)),
            (200, Data(#"{"id":"existing"}"#.utf8)), (200, bytes),
        ])
        let client = GoogleDriveBackupClient(transport: transport)
        let id = try await client.upload(
            encrypted: bytes, folderID: "folder", token: "example-token", installation: "deviceA")
        #expect(id == "existing")
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests[1].httpMethod == "PATCH")
        #expect(requests[1].httpBody == bytes)
        #expect(requests[1].httpBody?.range(of: Data("Private fixture note".utf8)) == nil)
        #expect(requests[0].url?.absoluteString.contains("deviceA") == true)
        #expect(requests[2].url?.absoluteString.contains("alt=media") == true)
    }

    @Test func ambiguousFilesAndFailedVerificationCannotReportSuccess() async throws {
        let bytes = try EncryptedBackup.seal(Data("Fixture".utf8), key: SymmetricKey(size: .bits256))
        let ambiguous = ScriptedDriveTransport([(200, Data(#"{"files":[{"id":"one"},{"id":"two"}]}"#.utf8))])
        let client = GoogleDriveBackupClient(transport: ambiguous)
        await #expect(throws: GoogleDriveBackupClient.Failure.self) {
            try await client.upload(encrypted: bytes, folderID: "folder", token: "example", installation: "deviceA")
        }
        #expect(await ambiguous.requests.count == 1)
        let mismatch = ScriptedDriveTransport([
            (200, Data(#"{"files":[{"id":"one","appProperties":{"blueInstallation":"deviceA"}}]}"#.utf8)),
            (200, Data()), (200, Data("wrong file".utf8)),
        ])
        await #expect(throws: GoogleDriveBackupClient.Failure.self) {
            try await GoogleDriveBackupClient(transport: mismatch).upload(
                encrypted: bytes, folderID: "folder", token: "example", installation: "deviceA")
        }
    }

    @Test func missingRecoveryKeyNeverGetsRecreatedWhileReading() async throws {
        let transport = ScriptedDriveTransport([(404, Data())])
        let client = GoogleDriveBackupClient(transport: transport)
        await #expect(throws: GoogleDriveBackupClient.Failure.self) {
            try await client.key(id: "missing", token: "example", createIfMissing: false)
        }
        #expect(await transport.requests.count == 1)
        #expect(await transport.requests.first?.httpMethod == "GET")
    }

    @Test func discoversExistingAppFolderWithoutCreatingAnother() async throws {
        let transport = ScriptedDriveTransport([(200, Data(#"{"files":[{"id":"folder","name":"Blue"}]}"#.utf8))])
        let client = GoogleDriveBackupClient(transport: transport)
        #expect(try await client.folder(token: "example", reservedID: "reserved") == "folder")
        #expect(await transport.requests.count == 1)
    }
}
