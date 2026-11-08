import Foundation

/// This client sends only an explicitly selected public title, never library contents or personal notes.
struct PublicFactsService: Sendable {
    func lookup(title: String, language: AppLanguage) async throws -> [WebSource] {
        guard !title.isEmpty, title.count <= 180 else { throw BlueError.invalidValue }
        var url = URLComponents(string: "https://\(language.rawValue).wikipedia.org/w/api.php")!
        url.queryItems = [
            URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"), URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: title), URLQueryItem(name: "gsrlimit", value: "3"),
            URLQueryItem(name: "prop", value: "extracts|info"), URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"), URLQueryItem(name: "exchars", value: "1400"),
            URLQueryItem(name: "inprop", value: "url"),
        ]
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        request.setValue("Blue/1.0 (https://github.com/iOrb/blue-app)", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else {
            throw BlueError.webUnavailable
        }
        struct Page: Decodable {
            var title: String
            var extract: String?
            var fullurl: URL?
            var index: Int?
        }
        struct Query: Decodable { var pages: [Page]? }
        struct Response: Decodable { var query: Query? }
        let pages = try JSONDecoder().decode(Response.self, from: data).query?.pages ?? []
        return pages.sorted { ($0.index ?? 100) < ($1.index ?? 100) }.compactMap { page in
            guard let summary = page.extract, !summary.isEmpty, let url = page.fullurl,
                url.scheme == "https", url.host == "\(language.rawValue).wikipedia.org"
            else { return nil }
            return WebSource(title: page.title, summary: String(summary.prefix(900)), url: url)
        }
    }
}
