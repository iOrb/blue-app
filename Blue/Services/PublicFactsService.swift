import Foundation
import Security

enum AssistantProvider: String, CaseIterable, Identifiable, Sendable {
    case openai, gemini, grok

    var id: String { rawValue }
    var title: String {
        switch self {
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        case .grok: "Grok"
        }
    }
    var models: [String] {
        switch self {
        case .openai: ["gpt-5-mini", "gpt-6-astra"]
        case .gemini: ["gemini-3.8-flash", "gemini-3.7-flash"]
        case .grok: ["grok-4.7", "grok-4.6"]
        }
    }
    var liveModels: [String] {
        switch self {
        case .openai: ["gpt-live-1", "gpt-realtime"]
        case .gemini: ["gemini-3.8-live", "gemini-3.1-flash-live-preview"]
        case .grok: ["grok-voice-latest", "grok-voice-3.0"]
        }
    }
    var transcriptionModels: [String] {
        switch self {
        case .openai: ["gpt-transcribe", "whisper-1"]
        case .gemini: ["gemini-3.8-flash", "gemini-3.7-flash"]
        case .grok: ["grok-voice-transcribe-2.0"]
        }
    }
}

struct AssistantConnection: Equatable, Sendable {
    static let credentialsDidChange = Notification.Name("BlueCredentialsChanged")
    let provider: AssistantProvider
    let model: String
    let key: String

    static var provider: AssistantProvider {
        UserDefaults.standard.string(forKey: "blue.assistant.provider").flatMap(AssistantProvider.init) ?? .openai
    }
    static func model(for provider: AssistantProvider) -> String {
        UserDefaults.standard.string(forKey: "blue.assistant.model." + provider.rawValue) ?? provider.models[0]
    }
    static func select(provider: AssistantProvider, model: String) {
        UserDefaults.standard.set(provider.rawValue, forKey: "blue.assistant.provider")
        UserDefaults.standard.set(model, forKey: "blue.assistant.model." + provider.rawValue)
    }
    static func voiceModel(for provider: AssistantProvider) -> String {
        preferredModel("voice", provider: provider, options: provider.liveModels)
    }
    static func transcriptionModel(for provider: AssistantProvider) -> String {
        preferredModel("transcription", provider: provider, options: provider.transcriptionModels)
    }
    static func selectVoice(_ model: String, for provider: AssistantProvider) {
        UserDefaults.standard.set(model, forKey: "blue.assistant.voice." + provider.rawValue)
    }
    static func selectTranscription(_ model: String, for provider: AssistantProvider) {
        UserDefaults.standard.set(model, forKey: "blue.assistant.transcription." + provider.rawValue)
    }
    private static func preferredModel(_ purpose: String, provider: AssistantProvider, options: [String]) -> String {
        let saved = UserDefaults.standard.string(forKey: "blue.assistant.\(purpose)." + provider.rawValue)
        return options.first(where: { $0 == saved }) ?? options[0]
    }
    static func isValidModel(_ model: String) -> Bool {
        !model.isEmpty && model.utf8.count <= 100
            && model.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                    || [45, 46, 95].contains($0)
            }
    }
    static func configured() -> Self? {
        let provider = Self.provider
        let model = model(for: provider)
        guard let key = key(for: provider), isValidModel(model) else { return nil }
        return Self(provider: provider, model: model, key: key)
    }
    private static func credential(for provider: AssistantProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.iorb.blue.assistant",
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
    static func key(for provider: AssistantProvider) -> String? {
        var query = credential(for: provider)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    static func setKey(_ input: String, for provider: AssistantProvider) throws {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count <= 512, !key.contains(where: \.isWhitespace) else { throw BlueError.invalidValue }
        let query = credential(for: provider) as CFDictionary
        if key.isEmpty {
            let status = SecItemDelete(query)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw BlueError.saveFailed }
            NotificationCenter.default.post(name: credentialsDidChange, object: nil)
            return
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = credential(for: provider)
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw BlueError.saveFailed }
        } else if status != errSecSuccess {
            throw BlueError.saveFailed
        }
        NotificationCenter.default.post(name: credentialsDidChange, object: nil)
    }
}

final class NoAssistantRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct ConnectedAssistant: Sendable {
    struct Reply: Sendable {
        var text = ""
        var sources: [WebSource] = []
    }

    let connection: AssistantConnection

    func modelCatalog() async throws -> [String] {
        let endpoint: String
        switch connection.provider {
        case .openai: endpoint = "https://api.openai.com/v1/models"
        case .gemini: endpoint = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000"
        case .grok: endpoint = "https://api.x.ai/v1/models"
        }
        guard let url = URL(string: endpoint) else { throw BlueError.invalidValue }
        var request = URLRequest(url: url, timeoutInterval: 15)
        if connection.provider == .gemini {
            request.setValue(connection.key, forHTTPHeaderField: "x-goog-api-key")
        } else {
            request.setValue("Bearer \(connection.key)", forHTTPHeaderField: "Authorization")
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoAssistantRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return try Self.models(from: data, provider: connection.provider)
        case 400 where connection.provider == .gemini && Self.invalidGeminiKey(in: data):
            throw BlueError.assistantCredentials
        case 401, 403: throw BlueError.assistantCredentials
        case 429: throw BlueError.assistantRateLimit
        default: throw BlueError.webUnavailable
        }
    }

    static func invalidGeminiKey(in data: Data) -> Bool {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = body?["error"] as? [String: Any]
        let details = error?["details"] as? [[String: Any]]
        return details?.contains { $0["reason"] as? String == "API_KEY_INVALID" } == true
    }

    static func models(from data: Data, provider: AssistantProvider) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root[provider == .gemini ? "models" : "data"] as? [[String: Any]]
        else { throw BlueError.invalidValue }
        let names = rows.flatMap { row -> [String] in
            if provider == .gemini {
                guard let methods = row["supportedGenerationMethods"] as? [String], methods.contains("generateContent"),
                    let name = row["name"] as? String, name.hasPrefix("models/")
                else { return [] }
                return [String(name.dropFirst("models/".count))]
            }
            return [row["id"] as? String].compactMap { $0 } + (row["aliases"] as? [String] ?? [])
        }
        let supported = names.filter { name in
            guard AssistantConnection.isValidModel(name) else { return false }
            let lower = name.lowercased()
            if [
                "audio", "realtime", "-live", "transcrib", "tts", "embedding", "image", "imagine", "video",
                "moderation",
                "search-api", "computer-use",
            ].contains(where: { lower.contains($0) }) {
                return false
            }
            switch provider {
            case .openai: return lower.hasPrefix("gpt-") || ["o1", "o3", "o4"].contains(where: { lower.hasPrefix($0) })
            case .gemini: return lower.hasPrefix("gemini-")
            case .grok: return lower.hasPrefix("grok-")
            }
        }
        return Set(supported).sorted()
    }

    func request(instructions: String, prompt: String, webSearch: Bool = true, libraryAction: Bool = false) throws
        -> URLRequest
    {
        guard AssistantConnection.isValidModel(connection.model) else { throw BlueError.invalidValue }
        let stream = connection.provider != .openai || !libraryAction
        let endpoint: String
        var body: [String: Any]
        if connection.provider == .gemini {
            endpoint =
                "https://generativelanguage.googleapis.com/v1beta/models/\(connection.model):streamGenerateContent?alt=sse"
            body = [
                "systemInstruction": ["parts": [["text": instructions]]],
                "contents": [["role": "user", "parts": [["text": prompt]]]],
                "tools": webSearch ? [["googleSearch": [String: String]()]] : [],
            ]
        } else {
            endpoint =
                connection.provider == .openai ? "https://api.openai.com/v1/responses" : "https://api.x.ai/v1/responses"
            body = [
                "model": connection.model,
                "input": [["role": "system", "content": instructions], ["role": "user", "content": prompt]],
                "tools": webSearch ? [["type": "web_search"]] : [],
                "store": false,
                "stream": stream,
            ]
            if connection.provider == .openai, libraryAction {
                let model = connection.model
                let structured = model.hasPrefix("gpt-5") || model.hasPrefix("gpt-6") || model.hasPrefix("gpt-4.1")
                body["text"] = ["format": structured ? ConnectedLibraryAgent.responseFormat : ["type": "json_object"]]
                if connection.model == "gpt-5-mini" { body["reasoning"] = ["effort": "minimal"] }
            }
        }
        guard let url = URL(string: endpoint) else { throw BlueError.invalidValue }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        if connection.provider == .gemini {
            request.setValue(connection.key, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("blue-ios/1.0", forHTTPHeaderField: "x-goog-api-client")
        } else {
            request.setValue("Bearer \(connection.key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func respond(
        instructions: String, prompt: String,
        webSearch: Bool = true,
        libraryAction: Bool = false,
        onText: @MainActor @Sendable (String) -> Void = { _ in }
    ) async throws -> Reply {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoAssistantRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let request = try request(
            instructions: instructions, prompt: prompt, webSearch: webSearch, libraryAction: libraryAction)
        if connection.provider == .openai, libraryAction {
            let (data, response) = try await session.data(for: request)
            try Self.checkResponse(response)
            return try Self.completedAction(data)
        }
        let (bytes, response) = try await session.bytes(for: request)
        try Self.checkResponse(response)
        var reply = Reply()
        var lastUpdate = ContinuousClock.now
        var completed = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if data == "[DONE]" { break }
            let update = try Self.chunk(Data(data.utf8), provider: connection.provider)
            completed = completed || update.completed
            reply.text += update.text
            guard reply.text.count <= 32_000 else { throw BlueError.invalidValue }
            for source in update.sources where !reply.sources.contains(where: { $0.url == source.url }) {
                if reply.sources.count < 12 { reply.sources.append(source) }
            }
            if !update.text.isEmpty, !Self.isAction(reply.text), lastUpdate.duration(to: .now) >= .milliseconds(70) {
                await onText(reply.text)
                lastUpdate = .now
            }
        }
        guard completed, !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BlueError.webUnavailable
        }
        return reply
    }

    private static func checkResponse(_ response: URLResponse) throws {
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: throw BlueError.assistantCredentials
        case 404: throw BlueError.assistantModelUnavailable
        case 429: throw BlueError.assistantRateLimit
        default: throw BlueError.webUnavailable
        }
    }

    static func completedAction(_ data: Data) throws -> Reply {
        guard data.count <= 1_048_576,
            let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            response["status"] as? String == "completed"
        else { throw BlueError.webUnavailable }
        let content = outputContent(response)
        let text = content.filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 32_000 else {
            throw BlueError.assistantResponseInvalid
        }
        return Reply(text: text, sources: citations(in: content))
    }

    static func isAction(_ text: String) -> Bool {
        let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.hasPrefix("{") || prefix.hasPrefix("`")
    }

    static func chunk(_ data: Data, provider: AssistantProvider) throws -> (
        text: String, sources: [WebSource], completed: Bool
    ) {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BlueError.webUnavailable
        }
        if provider == .gemini {
            guard let candidate = (event["candidates"] as? [[String: Any]])?.first else { return ("", [], false) }
            let content = candidate["content"] as? [String: Any]
            let parts = (content?["parts"] as? [[String: Any]] ?? []).filter { $0["thought"] as? Bool != true }
            let grounding = candidate["groundingMetadata"] as? [String: Any]
            let links = (grounding?["groundingChunks"] as? [[String: Any]] ?? []).compactMap {
                $0["web"] as? [String: Any]
            }
            return (
                parts.compactMap { $0["text"] as? String }.joined(),
                links.compactMap {
                    source(url: $0["uri"] as? String, title: $0["title"] as? String)
                }, candidate["finishReason"] as? String == "STOP"
            )
        }
        switch event["type"] as? String {
        case "response.output_text.delta":
            return (event["delta"] as? String ?? "", [], false)
        case "response.output_text.annotation.added":
            let annotation = event["annotation"] as? [String: Any]
            return (
                "",
                [source(url: annotation?["url"] as? String, title: annotation?["title"] as? String)].compactMap { $0 },
                false
            )
        case "response.completed":
            let response = event["response"] as? [String: Any] ?? [:]
            return ("", citations(in: outputContent(response)), true)
        case "response.failed", "response.incomplete", "error":
            throw BlueError.webUnavailable
        default: return ("", [], false)
        }
    }

    private static func outputContent(_ response: [String: Any]) -> [[String: Any]] {
        (response["output"] as? [[String: Any]] ?? []).flatMap { $0["content"] as? [[String: Any]] ?? [] }
    }

    private static func citations(in content: [[String: Any]]) -> [WebSource] {
        content.flatMap { $0["annotations"] as? [[String: Any]] ?? [] }
            .compactMap { source(url: $0["url"] as? String, title: $0["title"] as? String) }
    }

    private static func source(url: String?, title: String?) -> WebSource? {
        guard let url, let link = URL(string: url), link.scheme == "https", let host = link.host,
            link.user == nil, link.password == nil
        else { return nil }
        return WebSource(title: String((title ?? host).prefix(160)), summary: "", url: link)
    }
}

/// Used by the legacy model tools when they request public facts.
struct PublicFactsService: Sendable {
    func lookup(title: String, language: AppLanguage) async throws -> [WebSource] {
        guard !title.isEmpty, title.count <= 180 else { throw BlueError.invalidValue }
        guard let connection = AssistantConnection.configured() else { throw BlueError.assistantNotConfigured }
        let reply = try await ConnectedAssistant(connection: connection).respond(
            instructions:
                "Search the web for the public topic supplied by the user. Give one short factual sentence in \(language.rawValue).",
            prompt: title)
        return reply.sources.map { WebSource(title: $0.title, summary: String(reply.text.prefix(900)), url: $0.url) }
    }
}
