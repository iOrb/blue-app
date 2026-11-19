import CryptoKit
import Foundation

protocol DriveHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct DriveURLTransport: DriveHTTPTransport {
    let session: URLSession
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GoogleDriveBackupClient.Failure.response }
        return (data, response)
    }
}

/// Each installation updates only its own file. A fresh installation never overwrites another device.
actor GoogleDriveBackupClient {
    enum Failure: Error { case invalidInput, response, ambiguous, invalidEnvelope, notFound }
    struct File: Codable, Equatable, Sendable {
        let id: String
        let name: String?
        let trashed: Bool?
        let parents: [String]?
        let appProperties: [String: String]?
    }
    private struct Results: Decodable {
        let files: [File]
        let nextPageToken: String?
    }
    private struct IDs: Decodable { let ids: [String] }
    private let transport: any DriveHTTPTransport

    init(session: URLSession = .shared) { transport = DriveURLTransport(session: session) }
    init(transport: any DriveHTTPTransport) { self.transport = transport }

    func folder(token: String, reservedID: String) async throws -> String {
        let matches = try await list(
            query:
                "mimeType = 'application/vnd.google-apps.folder' and trashed = false and appProperties has { key='blueRole' and value='backups' }",
            token: token)
        guard matches.count <= 1 else { throw Failure.ambiguous }
        if let found = matches.first { return found.id }
        let metadata: [String: Any] = [
            "id": try validID(reservedID), "name": "Blue", "mimeType": "application/vnd.google-apps.folder",
            "appProperties": ["blueRole": "backups"],
        ]
        do { return try await create(metadata, token: token).id } catch Failure.response {
            // A repeated reserved ID can already exist after a lost response. Confirm its identity.
            let existing = try await file(id: reservedID, token: token)
            guard existing.trashed != true else { throw Failure.notFound }
            guard existing.appProperties?["blueRole"] == "backups" else { throw Failure.response }
            return existing.id
        }
    }

    func reserveID(token: String, space: String = "drive") async throws -> String {
        guard ["drive", "appDataFolder"].contains(space) else { throw Failure.invalidInput }
        let data = try await send(
            url: "https://www.googleapis.com/drive/v3/files/generateIds?count=1&space=\(space)", token: token)
        guard let id = try JSONDecoder().decode(IDs.self, from: data).ids.first else { throw Failure.response }
        return try validID(id)
    }

    func backup(in folder: String, installation: String, token: String, cachedID: String? = nil) async throws -> File? {
        if let cachedID {
            do {
                let existing = try await file(id: cachedID, token: token)
                guard existing.appProperties?["blueInstallation"] == installation else { throw Failure.response }
                if existing.trashed != true, existing.parents?.contains(folder) != false { return existing }
            } catch Failure.notFound {}
        }
        let folder = try validID(folder)
        let installation = try validID(installation)
        let matches = try await list(
            query:
                "'\(folder)' in parents and trashed = false and appProperties has { key='blueInstallation' and value='\(installation)' }",
            token: token)
        guard matches.count <= 1 else { throw Failure.ambiguous }
        if let first = matches.first, first.appProperties?["blueInstallation"] != installation {
            throw Failure.response
        }
        return matches.first
    }

    func listBackups(in folder: String, token: String) async throws -> [File] {
        try await list(
            query:
                "'\(validID(folder))' in parents and trashed = false and appProperties has { key='blueRole' and value='snapshot' }",
            token: token)
    }

    func upload(
        encrypted: Data, folderID: String, token: String,
        installation: String = "legacy", reservedID: String? = nil, cachedID: String? = nil
    ) async throws -> String {
        guard
            encrypted.starts(with: Data("BLUEBACKUP\u{0}\u{1}".utf8))
                || encrypted.starts(with: Data("BLUEBACKUP\u{0}\u{2}".utf8)), encrypted.count > 40,
            encrypted.count <= 50_000_000
        else { throw Failure.invalidEnvelope }
        let folderID = try validID(folderID)
        let installation = try validID(installation)
        let existing = try await backup(in: folderID, installation: installation, token: token, cachedID: cachedID)
        let id: String
        if let existing {
            id = existing.id
            _ = try await send(
                url: "https://www.googleapis.com/upload/drive/v3/files/\(validID(id))?uploadType=media",
                method: "PATCH", body: encrypted, contentType: "application/octet-stream", token: token)
        } else {
            guard let reservedID else { throw Failure.invalidInput }
            id = try validID(reservedID)
            let metadata: [String: Any] = [
                "id": id, "name": "Blue-\(installation.prefix(8)).bluebackup", "parents": [folderID],
                "appProperties": ["blueRole": "snapshot", "blueInstallation": installation],
            ]
            let boundary = UUID().uuidString
            var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
            body.append(try JSONSerialization.data(withJSONObject: metadata))
            body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(encrypted)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            do {
                _ = try await send(
                    url: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart", method: "POST",
                    body: body, contentType: "multipart/related; boundary=\(boundary)", token: token)
            } catch {
                let prior = try await file(id: id, token: token)
                guard prior.appProperties?["blueInstallation"] == installation else { throw Failure.response }
                // Do not overwrite a file whose earlier creation may already have completed.
            }
        }
        guard try await download(id: id, token: token) == encrypted else { throw Failure.response }
        return id
    }

    func download(id: String, token: String) async throws -> Data {
        try await send(url: "https://www.googleapis.com/drive/v3/files/\(validID(id))?alt=media", token: token)
    }

    func key(id: String, token: String, createIfMissing: Bool) async throws -> Data {
        do {
            let existing = try await download(id: id, token: token)
            guard existing.count == 32 else { throw Failure.invalidEnvelope }
            return existing
        } catch Failure.notFound {
            guard createIfMissing else { throw Failure.notFound }
        }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let boundary = UUID().uuidString
        let metadata: [String: Any] = [
            "id": try validID(id), "name": "Blue recovery key", "parents": ["appDataFolder"],
        ]
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(key)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        do {
            _ = try await send(
                url: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart", method: "POST",
                body: body,
                contentType: "multipart/related; boundary=\(boundary)", token: token)
        } catch {
            let existing = try await download(id: id, token: token)
            guard existing.count == 32 else { throw Failure.response }
            return existing
        }
        guard try await download(id: id, token: token) == key else { throw Failure.response }
        return key
    }

    private func file(id: String, token: String) async throws -> File {
        let data = try await send(
            url:
                "https://www.googleapis.com/drive/v3/files/\(validID(id))?fields=id,name,trashed,parents,appProperties",
            token: token)
        return try JSONDecoder().decode(File.self, from: data)
    }
    private func list(query: String, token: String) async throws -> [File] {
        var url = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        url.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,trashed,appProperties)"),
            URLQueryItem(name: "pageSize", value: "100"),
        ]
        let result = try JSONDecoder().decode(
            Results.self, from: await send(url: url.url!.absoluteString, token: token))
        guard result.nextPageToken == nil else { throw Failure.ambiguous }
        return result.files
    }
    private func create(_ metadata: [String: Any], token: String) async throws -> File {
        let data = try await send(
            url: "https://www.googleapis.com/drive/v3/files?fields=id,name,trashed,parents,appProperties",
            method: "POST",
            body: JSONSerialization.data(withJSONObject: metadata), contentType: "application/json", token: token)
        return try JSONDecoder().decode(File.self, from: data)
    }
    private func send(url: String, method: String = "GET", body: Data? = nil, contentType: String? = nil, token: String)
        async throws -> Data
    {
        guard !token.isEmpty else { throw Failure.invalidInput }
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 45)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 404 { throw Failure.notFound }
        guard (200..<300).contains(response.statusCode), data.count <= 50_000_000 else { throw Failure.response }
        return data
    }
    private func validID(_ input: String) throws -> String {
        guard !input.isEmpty, input.utf8.count <= 200,
            input.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
            })
        else { throw Failure.invalidInput }
        return input
    }
}
