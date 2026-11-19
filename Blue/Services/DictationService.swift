import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class DictationService {
    private(set) var recording = false
    private(set) var transcribing = false
    private(set) var errorKey: String?
    private var recorder: AVAudioRecorder?
    private var file: URL?
    private var active = false
    private var generation = UUID()
    private var captureTimeout: Task<Void, Never>?
    private var task: Task<Void, Never>?

    func start(
        connection: AssistantConnection, model: String, language: AppLanguage,
        onText: @escaping @MainActor (String) -> Void
    ) async {
        stop()
        errorKey = nil
        let id = generation
        guard await AVAudioApplication.requestRecordPermission(), generation == id else {
            if generation == id { errorKey = "dictation.permission" }
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            active = true
            let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension(
                "m4a")
            self.file = file
            let recorder = try AVAudioRecorder(
                url: file,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24_000,
                    AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000,
                ])
            self.recorder = recorder
            guard recorder.record(forDuration: 60) else { throw BlueError.unsupported }
            recording = true
            captureTimeout = Task {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled, generation == id {
                    finish(connection: connection, model: model, language: language, onText: onText)
                }
            }
        } catch {
            stop()
            errorKey = "dictation.unavailable"
        }
    }

    func finish(
        connection: AssistantConnection, model: String, language: AppLanguage,
        onText: @escaping @MainActor (String) -> Void
    ) {
        guard recording, let file else { return }
        captureTimeout?.cancel()
        stopAudio()
        transcribing = true
        let id = generation
        task = Task {
            defer {
                try? FileManager.default.removeItem(at: file)
                if generation == id {
                    self.file = nil
                    transcribing = false
                }
            }
            do {
                let text = try await Self.transcribe(
                    Data(contentsOf: file), connection: connection, model: model, language: language)
                guard generation == id, !Task.isCancelled else { return }
                if text.isEmpty { errorKey = "dictation.noSpeech" } else { onText(text) }
            } catch {
                if generation == id, !Task.isCancelled {
                    errorKey = (error as? BlueError)?.key ?? "dictation.unavailable"
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        captureTimeout?.cancel()
        task?.cancel()
        stopAudio()
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        transcribing = false
    }

    private func stopAudio() {
        recorder?.stop()
        recorder = nil
        recording = false
        if active { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        active = false
    }

    nonisolated static func transcriptionRequest(
        _ audio: Data, connection: AssistantConnection, model: String, language: AppLanguage
    ) throws -> URLRequest {
        guard connection.provider.transcriptionModels.contains(model), !audio.isEmpty, audio.count <= 1_000_000
        else { throw BlueError.invalidValue }
        let address: String
        switch connection.provider {
        case .openai: address = "https://api.openai.com/v1/audio/transcriptions"
        case .grok: address = "https://api.x.ai/v1/stt"
        case .gemini: address = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        }
        var request = URLRequest(url: URL(string: address)!, timeoutInterval: 35)
        request.httpMethod = "POST"
        if connection.provider == .gemini {
            request.setValue(connection.key, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "contents": [
                    [
                        "parts": [
                            [
                                "text":
                                    "Transcribe the audio exactly in its original language. Return only the transcript or an empty response for silence."
                            ],
                            ["inlineData": ["mimeType": "audio/mp4", "data": audio.base64EncodedString()]],
                        ]
                    ]
                ]
            ])
        } else {
            let boundary = UUID().uuidString
            request.setValue("Bearer " + connection.key, forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            for (name, value) in [("model", model), ("language", language.rawValue)] {
                body.append(
                    Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            }
            body.append(
                Data(
                    "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n"
                        .utf8))
            body.append(audio)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            request.httpBody = body
        }
        return request
    }

    private nonisolated static func transcribe(
        _ audio: Data, connection: AssistantConnection, model: String, language: AppLanguage
    ) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: NoAssistantRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let request = try transcriptionRequest(audio, connection: connection, model: model, language: language)
        let (data, response) = try await session.data(for: request)
        try VoiceProtocol.check(response)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if connection.provider == .gemini {
            let candidate = (root?["candidates"] as? [[String: Any]])?.first
            let content = candidate?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]] ?? []
            return parts.filter { $0["thought"] as? Bool != true }
                .compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (root?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
