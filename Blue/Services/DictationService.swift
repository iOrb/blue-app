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

    func start(language: AppLanguage, onText: @escaping @MainActor (String) -> Void) async {
        stop()
        errorKey = nil
        let generation = UUID()
        self.generation = generation
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard permission == .authorized, await AVAudioApplication.requestRecordPermission() else {
            errorKey = "dictation.permission"
            return
        }
        guard self.generation == generation else { return }
        guard let recognizer = SFSpeechRecognizer(locale: language.locale), recognizer.isAvailable,
            recognizer.supportsOnDeviceRecognition
        else {
            errorKey = "dictation.unavailable"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.engine = engine
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw BlueError.unsupported }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
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
    func stop() {
        let usedAudio = engine != nil
        generation = UUID()
        engine?.stop()
        if engine != nil { engine?.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        engine = nil
        request = nil
        recording = false
        if usedAudio { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
