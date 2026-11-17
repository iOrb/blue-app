#if os(iOS)
    import AuthenticationServices
    import Foundation
    import Observation
    import Security
    import UIKit

    enum GoogleDriveConfiguration {
        static let clientID = "986940080652-n0h197enieffheihatctvnva4n19vs20.apps.googleusercontent.com"
        static let scope = "https://www.googleapis.com/auth/drive.file"
        static let backupScope = "https://www.googleapis.com/auth/drive.appdata"
        static let authorizationScope = scope + " " + backupScope
    }

    struct GoogleDriveTokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var scopes: String?
        var expiresAt: Date

        static func decode(_ data: Data, previousRefresh: String? = nil, now: Date = .now) throws -> Self {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(TokenResponse.self, from: data)
            guard result.tokenType.lowercased() == "bearer", !result.accessToken.isEmpty,
                result.expiresIn > 0, let refresh = result.refreshToken ?? previousRefresh, !refresh.isEmpty,
                result.scope?.split(separator: " ").contains(Substring(GoogleDriveConfiguration.scope)) == true
                    || (previousRefresh != nil && result.scope == nil)
            else { throw BlueError.permissionDenied }
            return Self(
                accessToken: result.accessToken, refreshToken: refresh, scopes: result.scope,
                expiresAt: now.addingTimeInterval(result.expiresIn))
        }
        private struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Double
            let scope: String?
            let tokenType: String
        }
    }

    @MainActor @Observable
    final class GoogleDriveConnection: NSObject, ASWebAuthenticationPresentationContextProviding, DriveBackupConnection
    {
        private(set) var connected = false
        private(set) var hasBackupPermission = false
        private(set) var busy = false
        private(set) var account: String?
        private(set) var errorKey: String?
        private var authentication: ASWebAuthenticationSession?
        private var task: Task<Void, Never>?
        private let network: URLSession

        override init() {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            network = URLSession(configuration: configuration, delegate: NoAssistantRedirects(), delegateQueue: nil)
            super.init()
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }

        func restore() {
            guard !busy, !connected else { return }
            guard let tokens = try? Self.readTokens() else { return }
            busy = true
            errorKey = nil
            task = Task {
                defer { busy = false }
                do {
                    let current = try await refreshed(tokens)
                    let identity = try await identity(token: current.accessToken)
                    try Task.checkCancellation()
                    try Self.store(current)
                    account = identity
                    hasBackupPermission =
                        current.scopes?.split(separator: " ").contains(Substring(GoogleDriveConfiguration.backupScope))
                        == true
                    connected = true
                } catch is CancellationError {
                } catch { errorKey = "drive.failed" }
            }
        }

        func connect() {
            guard !busy else { return }
            busy = true
            errorKey = nil
            task = Task {
                defer {
                    busy = false
                    authentication = nil
                }
                do {
                    let request = try GoogleOAuthRequest(
                        clientID: GoogleDriveConfiguration.clientID, scope: GoogleDriveConfiguration.authorizationScope)
                    let callback = try await authenticate(request)
                    let code = try request.code(from: callback)
                    let tokens = try await exchange([
                        "client_id": GoogleDriveConfiguration.clientID,
                        "code": code, "code_verifier": request.verifier,
                        "redirect_uri": request.redirectURI, "grant_type": "authorization_code",
                    ])
                    let identity = try await identity(token: tokens.accessToken)
                    try Task.checkCancellation()
                    try Self.store(tokens)
                    account = identity
                    hasBackupPermission =
                        tokens.scopes?.split(separator: " ").contains(Substring(GoogleDriveConfiguration.backupScope))
                        == true
                    connected = true
                } catch is CancellationError {
                } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                } catch { errorKey = "drive.failed" }
            }
        }

        func disconnect() {
            guard !busy else { return }
            let status = SecItemDelete(Self.query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                errorKey = "drive.failed"
                return
            }
            connected = false
            hasBackupPermission = false
            account = nil
            errorKey = nil
        }

        private func authenticate(_ request: GoogleOAuthRequest) async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: request.authorizationURL,
                    callbackURLScheme: URL(string: request.redirectURI)?.scheme
                ) { callback, error in
                    if let callback {
                        continuation.resume(returning: callback)
                    } else {
                        continuation.resume(throwing: error ?? GoogleOAuthRequest.Failure.invalidCallback)
                    }
                }
                session.presentationContextProvider = self
                authentication = session
                if !session.start() { continuation.resume(throwing: GoogleOAuthRequest.Failure.invalidConfiguration) }
            }
        }

        func accessToken() async throws -> String {
            guard connected, hasBackupPermission, let tokens = try Self.readTokens() else {
                throw BlueError.permissionDenied
            }
            let current = try await refreshed(tokens)
            try Self.store(current)
            return current.accessToken
        }

        private func refreshed(_ tokens: GoogleDriveTokens) async throws -> GoogleDriveTokens {
            if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens }
            var renewed = try await exchange(
                [
                    "client_id": GoogleDriveConfiguration.clientID, "grant_type": "refresh_token",
                    "refresh_token": tokens.refreshToken,
                ], previousRefresh: tokens.refreshToken)
            if renewed.scopes == nil { renewed.scopes = tokens.scopes }
            return renewed
        }

        private func exchange(_ fields: [String: String], previousRefresh: String? = nil) async throws
            -> GoogleDriveTokens
        {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let allowed = CharacterSet(
                charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            request.httpBody = Data(
                fields.sorted { $0.key < $1.key }.map {
                    $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value
                        .addingPercentEncoding(withAllowedCharacters: allowed)!
                }.joined(separator: "&").utf8)
            let (data, response) = try await network.data(for: request)
            try Self.check(response)
            return try GoogleDriveTokens.decode(data, previousRefresh: previousRefresh)

        }

        private func identity(token: String) async throws -> String {
            var request = URLRequest(
                url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)")!,
                timeoutInterval: 20)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (data, response) = try await network.data(for: request)
            try Self.check(response)
            let value = try JSONDecoder().decode(DriveIdentity.self, from: data)
            return value.user.emailAddress
        }
        private static func check(_ response: URLResponse) throws {
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw BlueError.permissionDenied
            }
        }
        private struct DriveIdentity: Decodable {
            struct User: Decodable { let emailAddress: String }
            let user: User
        }
        private static var query: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.iorb.blue.drive",
                kSecAttrAccount as String: "google",
            ]
        }
        private static func readTokens() throws -> GoogleDriveTokens? {
            var query = Self.query
            query[kSecReturnData as String] = true
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else { throw BlueError.saveFailed }
            return try JSONDecoder().decode(GoogleDriveTokens.self, from: data)
        }
        private static func store(_ tokens: GoogleDriveTokens) throws {
            let data = try JSONEncoder().encode(tokens)
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var attributes = query
                attributes[kSecValueData as String] = data
                attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw BlueError.saveFailed }
            } else if status != errSecSuccess {
                throw BlueError.saveFailed
            }
        }
    }
#endif
