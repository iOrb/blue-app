import Foundation
import Testing

@testable import Blue

struct GoogleDriveTokenTests {
    @Test func verifiesDrivePermissionAndKeepsRefreshCredentials() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let initial = Data(
            #"{"access_token":"example-access","refresh_token":"example-refresh","expires_in":3600,"token_type":"Bearer","scope":"https://www.googleapis.com/auth/drive.file"}"#
                .utf8)
        let tokens = try GoogleDriveTokens.decode(initial, now: now)
        #expect(tokens.refreshToken == "example-refresh")
        #expect(tokens.expiresAt == now.addingTimeInterval(3600))
        let refreshed = Data(#"{"access_token":"new-access","expires_in":3600,"token_type":"Bearer"}"#.utf8)
        #expect(
            try GoogleDriveTokens.decode(refreshed, previousRefresh: tokens.refreshToken).refreshToken
                == tokens.refreshToken)
        #expect(throws: BlueError.permissionDenied) { try GoogleDriveTokens.decode(refreshed) }
        let denied = Data(
            #"{"access_token":"example-access","refresh_token":"example-refresh","expires_in":3600,"token_type":"Bearer","scope":"openid"}"#
                .utf8)
        #expect(throws: BlueError.permissionDenied) { try GoogleDriveTokens.decode(denied) }
    }
}
