import Foundation
import Observation

/// User-selected File Provider directory. Each device owns one file, so it never overwrites another device's copy.
@MainActor @Observable
final class FolderBackupService {
    private(set) var folderName: String?
    private(set) var savedAt: Date?
    private(set) var saving = false
    private(set) var errorKey: String?
    private let defaults: UserDefaults
    private let writer = FolderBackupWriter()
    private var pending: Task<Void, Never>?
    private var generation = UUID()
    private var bookmark: Data?
    let filename: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedBookmark = defaults.data(forKey: "blue.backup.bookmark")
        bookmark = storedBookmark
        folderName = storedBookmark == nil ? nil : defaults.string(forKey: "blue.backup.folder")
        let device = defaults.string(forKey: "blue.backup.device") ?? UUID().uuidString
        defaults.set(device, forKey: "blue.backup.device")
        filename = "Blue-" + device + ".json"
    }

    func connect(to folder: URL, state: LibraryState) async throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let next = try folder.bookmarkData(
            options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        // Prove the destination is writable before replacing the current connection.
        try await writer.write(state, bookmark: next, filename: filename)
        generation = UUID()
        pending?.cancel()
        bookmark = next
        folderName = folder.lastPathComponent
        defaults.set(next, forKey: "blue.backup.bookmark")
        defaults.set(folderName, forKey: "blue.backup.folder")
        savedAt = .now
        saving = false
        errorKey = nil
    }

    func schedule(_ state: LibraryState, delay: Duration = .milliseconds(650)) {
        guard let bookmark else { return }
        pending?.cancel()
        let id = UUID()
        generation = id
        pending = Task {
            do {
                try await Task.sleep(for: delay)
                guard generation == id else { return }
                saving = true
                try await writer.write(state, bookmark: bookmark, filename: filename)
                guard generation == id else { return }
                savedAt = .now
                errorKey = nil
            } catch is CancellationError {
                return
            } catch {
                if generation == id {
                    savedAt = nil
                    errorKey = "backup.failed"
                }
            }
            if generation == id { saving = false }
        }
    }

    func disconnect() {
        generation = UUID()
        pending?.cancel()
        pending = nil
        bookmark = nil
        folderName = nil
        saving = false
        savedAt = nil
        errorKey = nil
        defaults.removeObject(forKey: "blue.backup.bookmark")
        defaults.removeObject(forKey: "blue.backup.folder")
    }
}

private actor FolderBackupWriter {
    func write(_ state: LibraryState, bookmark: Data, filename: String) throws {
        try Task.checkCancellation()
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
        guard !stale else { throw BlueError.saveFailed }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw BlueError.saveFailed
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try Task.checkCancellation()
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: .forMerging, error: &coordinationError) {
            directory in
            do {
                let target = directory.appending(path: filename)
                try data.write(to: target, options: .atomic)
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
