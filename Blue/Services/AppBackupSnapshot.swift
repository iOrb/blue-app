import Foundation

/// A complete app-owned snapshot, encoded only inside an authenticated encrypted container.
/// Device permissions, system alarms and the storage bookmark must be re-established on restore.
struct AppBackupSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version: Int = currentVersion
    var library: LibraryState
    var preferences: [String: String]
    var credentials: [String: String]

    @MainActor
    static func capture(
        library: LibraryState, defaults: UserDefaults = .standard,
        credential: (AssistantProvider) -> String? = { AssistantConnection.key(for: $0) }
    ) -> Self {
        let generalKeys = ["blue.language", "blue.appearance", "blue.assistant.provider"]
        let modelKeys = AssistantProvider.allCases.flatMap { provider in
            ["model", "voice", "transcription"].map { "blue.assistant.\($0).\(provider.rawValue)" }
        }
        let preferences = Dictionary(
            uniqueKeysWithValues: (generalKeys + modelKeys).compactMap { key in
                defaults.string(forKey: key).map { (key, $0) }
            })
        let credentials = Dictionary(
            uniqueKeysWithValues: AssistantProvider.allCases.compactMap { provider in
                credential(provider).map { (provider.rawValue, $0) }
            })
        return Self(library: library, preferences: preferences, credentials: credentials)
    }
}
