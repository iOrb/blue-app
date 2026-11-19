import CryptoKit
import Foundation
import Security

/// Builds one native-app OAuth request with a fresh state and PKCE verifier.
struct GoogleOAuthRequest: Sendable {
    enum Failure: Error { case invalidConfiguration, random, invalidCallback }
    let authorizationURL: URL
    let redirectURI: String
    let state: String
    let verifier: String

    init(clientID: String, scope: String) throws {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix), clientID.count > suffix.count,
            clientID.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46
            }),
            !scope.isEmpty
        else { throw Failure.invalidConfiguration }
        let random = try Self.randomBytes(count: 32)
        verifier = Self.base64url(random)
        state = Self.base64url(try Self.randomBytes(count: 32))
        let reversed = "com.googleusercontent.apps." + clientID.dropLast(suffix.count)
        redirectURI = String(reversed) + ":/oauth2redirect"
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authorizationURL = url.url else { throw Failure.invalidConfiguration }
        self.authorizationURL = authorizationURL
    }

    func code(from callback: URL) throws -> String {
        guard let expected = URLComponents(string: redirectURI),
            let actual = URLComponents(url: callback, resolvingAgainstBaseURL: false),
            actual.scheme == expected.scheme, actual.host == expected.host, actual.path == expected.path,
            let items = actual.queryItems,
            items.filter({ $0.name == "state" }).count == 1,
            items.first(where: { $0.name == "state" })?.value == state,
            items.filter({ $0.name == "code" }).count == 1,
            let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
            !items.contains(where: { $0.name == "error" })
        else { throw Failure.invalidCallback }
        return code
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw Failure.random }
        return Data(bytes)
    }
    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
