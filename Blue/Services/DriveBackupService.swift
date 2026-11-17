import CryptoKit
import Foundation
import Observation

@MainActor
protocol DriveBackupConnection: AnyObject {
    var connected: Bool { get }
    var hasBackupPermission: Bool { get }
    var account: String? { get }
    func accessToken() async throws -> String
}

/// Serializes writes and coalesces newer snapshots without cancelling an in-flight upload.
@MainActor @Observable
final class DriveBackupService {
    private(set) var savedAt: Date?
    private(set) var saving = false
    private(set) var errorKey: String?
    private(set) var folderID: String?
    private var pending: AppBackupSnapshot?
    private var needsVerification = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var lastSaved: AppBackupSnapshot?
    private let defaults: UserDefaults
    private let client: GoogleDriveBackupClient
    private let installation: String

    init(defaults: UserDefaults = .standard, client: GoogleDriveBackupClient = GoogleDriveBackupClient()) {
        self.defaults = defaults
        self.client = client
        let installation = defaults.string(forKey: "blue.drive.installation") ?? UUID().uuidString
        defaults.set(installation, forKey: "blue.drive.installation")
        self.installation = installation
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        pending = nil
        needsVerification = false
        lastSaved = nil
        savedAt = nil
        folderID = nil
        saving = false
        errorKey = nil
    }

    func schedule(_ snapshot: AppBackupSnapshot, connection: any DriveBackupConnection, verify: Bool = false) {
        guard connection.connected, connection.hasBackupPermission else { return }
        if !verify, snapshot == lastSaved, task == nil { return }
        pending = snapshot
        needsVerification = needsVerification || verify
        guard task == nil, let account = connection.account else { return }
        let id = generation
        task = Task {
            defer {
                if generation == id {
                    task = nil
                    saving = false
                }
            }
            do {
                try await Task.sleep(for: .milliseconds(650))
                while let snapshot = pending {
                    pending = nil
                    let verify = needsVerification
                    needsVerification = false
                    if snapshot == lastSaved, !verify { continue }
                    guard generation == id, connection.account == account, connection.hasBackupPermission else {
                        return
                    }
                    saving = true
                    let token = try await connection.accessToken()
                    let accountID = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
                    let prefix = "blue.drive." + accountID + "."
                    let folderCreateID = try await reservedID(prefix + "folder", space: "drive", token: token)
                    let folder: String
                    do {
                        folder = try await client.folder(token: token, reservedID: folderCreateID)
                    } catch GoogleDriveBackupClient.Failure.notFound {
                        defaults.removeObject(forKey: prefix + "folder")
                        let replacement = try await reservedID(prefix + "folder", space: "drive", token: token)
                        folder = try await client.folder(token: token, reservedID: replacement)
                    }
                    let backup = try await client.backup(
                        in: folder, installation: installation, token: token,
                        cachedID: defaults.string(forKey: prefix + "savedFileID"))
                    let keyID: String
                    let key: Data
                    if let backup {
                        // Resolve the key referenced by the existing file. Never replace an unreadable backup.
                        let previous = try DriveSnapshotEnvelope.decode(
                            await client.download(id: backup.id, token: token))
                        keyID = previous.keyID
                        key = try await client.key(id: keyID, token: token, createIfMissing: false)
                        _ = try previous.open(key: key)
                    } else {
                        keyID = try await reservedID(prefix + "key", space: "appDataFolder", token: token)
                        key = try await client.key(id: keyID, token: token, createIfMissing: true)
                    }
                    let encrypted = try await Task.detached {
                        try DriveSnapshotEnvelope.seal(snapshot, keyID: keyID, key: key)
                    }.value
                    try Task.checkCancellation()
                    guard generation == id, connection.account == account else { return }
                    let createID: String?
                    if backup == nil {
                        createID = try await reservedID(prefix + "file", space: "drive", token: token)
                    } else {
                        createID = nil
                    }
                    let uploadedID = try await client.upload(
                        encrypted: encrypted, folderID: folder, token: token, installation: installation,
                        reservedID: createID, cachedID: backup?.id)
                    guard generation == id else { return }
                    defaults.set(uploadedID, forKey: prefix + "savedFileID")
                    defaults.removeObject(forKey: prefix + "file")
                    folderID = folder
                    lastSaved = snapshot
                    savedAt = .now
                    errorKey = nil
                }
            } catch is CancellationError {
            } catch {
                if generation == id {
                    errorKey = "drive.backupFailed"
                    savedAt = nil
                }
            }
        }
    }

    /// Other Blue clients in the same Google project can read the visible file with the same account.
    func readSnapshot(fileID: String, connection: any DriveBackupConnection) async throws -> AppBackupSnapshot {
        let token = try await connection.accessToken()
        let envelope = try DriveSnapshotEnvelope.decode(await client.download(id: fileID, token: token))
        let key = try await client.key(id: envelope.keyID, token: token, createIfMissing: false)
        return try await Task.detached { try envelope.open(key: key) }.value
    }

    private func reservedID(_ preference: String, space: String, token: String) async throws -> String {
        if let value = defaults.string(forKey: preference) { return value }
        let id = try await client.reserveID(token: token, space: space)
        defaults.set(id, forKey: preference)
        return id
    }
}
