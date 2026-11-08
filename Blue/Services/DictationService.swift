import AVFoundation
import Observation
import Speech

@MainActor @Observable
final class DictationService {
    private(set) var recording = false
    private(set) var errorKey: String?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var hasRecordingTap = false
    private var audioSessionActive = false

    func start(language: AppLanguage, onText: @escaping @MainActor (String) -> Void) async {
        stop()
        errorKey = nil
        let generation = UUID()
        self.generation = generation
        let permission: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
        }
        guard self.generation == generation else { return }
        let hasPermission = permission == .authorized ? await AVAudioApplication.requestRecordPermission() : false
        guard self.generation == generation else { return }
        guard hasPermission else {
            errorKey = "dictation.permission"
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: language.locale), recognizer.isAvailable,
            recognizer.supportsOnDeviceRecognition
        else {
            errorKey = "dictation.unavailable"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            audioSessionActive = true
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.engine = engine
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let hardware = input.inputFormat(forBus: 0)
            guard hardware.sampleRate > 0, hardware.channelCount > 0, format.sampleRate > 0, format.channelCount > 0
            else { throw BlueError.unsupported }
            Self.installRecordingTap(on: input, format: format, request: request)
            hasRecordingTap = true
            recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true || error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    if let text { onText(text) }
                    if finished { self.stop() }
                }
            }
            engine.prepare()
            try engine.start()
            recording = true
        } catch {
            stop()
            errorKey = "dictation.unavailable"
        }
    }
    // AVAudioEngine delivers this callback on its audio queue.
    private nonisolated static func installRecordingTap(
        on input: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    func stop() {
        generation = UUID()
        engine?.stop()
        if hasRecordingTap { engine?.inputNode.removeTap(onBus: 0) }
        hasRecordingTap = false
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        engine = nil
        request = nil
        recording = false
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
    }
}
