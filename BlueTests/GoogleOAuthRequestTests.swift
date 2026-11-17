import Foundation
import Testing

@testable import Blue

struct GoogleOAuthRequestTests {
    @Test func usesFreshStateAndRejectsUntrustedCallbacks() throws {
        let clientID = "123456789-example.apps.googleusercontent.com"
        let first = try GoogleOAuthRequest(clientID: clientID, scope: "https://www.googleapis.com/auth/drive.file")
        let second = try GoogleOAuthRequest(clientID: clientID, scope: "https://www.googleapis.com/auth/drive.file")
        #expect(first.state != second.state)
        #expect(first.verifier != second.verifier)
        let query = try #require(URLComponents(url: first.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
        let valid = try #require(URL(string: first.redirectURI + "?code=example&state=" + first.state))
        #expect(try first.code(from: valid) == "example")
        let invalid = try #require(URL(string: first.redirectURI + "?code=example&state=" + second.state))
        #expect(throws: GoogleOAuthRequest.Failure.self) { try first.code(from: invalid) }
        #expect(throws: GoogleOAuthRequest.Failure.self) {
            try first.code(from: URL(string: "https://example.com/?code=example&state=" + first.state)!)
        }
    }
}
