#if os(iOS)
    import AVFoundation
    import Foundation
    import Observation
    import Synchronization

    @MainActor @Observable
    final class LiveVoiceService {
        enum Phase: Equatable { case idle, connecting, listening, speaking, working, muted, failed }
        private(set) var phase: Phase = .idle
        private(set) var muted = false
        private(set) var level: Double = 0
        private(set) var errorKey: String?
        private(set) var inputWarningKey: String?
        private(set) var caption = ""

        private var generation = UUID()
        private var task: Task<Void, Never>?
        private var sending: Task<Void, Never>?
        private var timeout: Task<Void, Never>?
        private var work: Task<Void, Never>?
        private var playbackWatch: Task<Void, Never>?
        private var captureWatch: Task<Void, Never>?
        private var lastAudioSent: ContinuousClock.Instant?
        private var silentInputSince: ContinuousClock.Instant?
        private var network: URLSession?
        private var socket: URLSessionWebSocketTask?
        private var wire: VoiceProtocol?
        private var audio: LiveVoiceAudio?
        private var pending: [VoiceProtocol.ToolCall] = []
        private var completed: Set<String> = []
        private var runningCalls: Set<String> = []
        private var responseOutstanding = false
        private var speech = ""
        private var reply = ""
        private var onExchange: ((String, String) -> Void)?

        func start(
            connection: AssistantConnection, model: String, language: AppLanguage,
            onExchange: @escaping (String, String) -> Void,
            perform: @escaping (VoiceProtocol.ToolCall) async throws -> String
        ) {
            stop()
            let id = generation
            self.onExchange = onExchange
            let wire = VoiceProtocol(connection: connection, model: model)
            self.wire = wire
            phase = .connecting
            task = Task {
                guard await AVAudioApplication.requestRecordPermission(), generation == id else {
                    if generation == id { fail("dictation.permission") }
                    return
                }
                do {
                    let config = URLSessionConfiguration.ephemeral
                    config.httpShouldSetCookies = false
                    let network = URLSession(
                        configuration: config, delegate: NoAssistantRedirects(), delegateQueue: nil)
                    self.network = network
                    let request = try await wire.socketRequest(in: network)
                    try Task.checkCancellation()
                    guard generation == id else { return }
                    let socket = network.webSocketTask(with: request)
                    socket.maximumMessageSize = 1_048_576
                    self.socket = socket
                    socket.resume()
                    timeout = Task {
                        try? await Task.sleep(for: .seconds(15))
                        if !Task.isCancelled, generation == id, phase == .connecting { fail("voice.connectionFailed") }
                    }
                    try await Self.send(wire.start(language: language), to: socket)
                    while !Task.isCancelled, generation == id {
                        let frame = try await socket.receive()
                        let data: Data
                        switch frame {
                        case .string(let text): data = Data(text.utf8)
                        case .data(let bytes): data = bytes
                        @unknown default: continue
                        }
                        for event in try wire.events(data) {
                            guard generation == id else { return }
                            try await handle(event, id: id, wire: wire, socket: socket, perform: perform)
                        }
                    }
                } catch {
                    guard generation == id, !Task.isCancelled else { return }
                    let key: String
                    if let http = socket?.response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403
                    {
                        key = BlueError.assistantCredentials.key
                    } else {
                        key = (error as? BlueError)?.key ?? "voice.connectionFailed"
                    }
                    fail(key)
                }
            }
        }

        #if DEBUG
            func startFixture() {
                stop()
                phase = .listening
            }
        #endif

        func toggleMute() {
            guard phase != .idle, phase != .failed else { return }
            muted.toggle()
            inputWarningKey = nil
            silentInputSince = nil
            level = 0
            #if DEBUG
                if audio == nil, phase == .listening || phase == .muted {
                    phase = muted ? .muted : .listening
                    return
                }
            #endif
            lastAudioSent = nil
            do { try audio?.setCaptureEnabled(!muted) } catch {
                fail("dictation.unavailable")
                return
            }
            if phase != .connecting && phase != .speaking && phase != .working { updatePhase() }
            guard let wire, let command = wire.mute(muted), let socket, audio != nil else { return }
            let id = generation
            Task {
                do { try await Self.send(command, to: socket) } catch {
                    if generation == id { fail("voice.connectionFailed") }
                }
            }
        }

        func stop() {
            let previous = socket
            let previousNetwork = network
            let closeLive = wire?.dialect == .live && audio != nil
            generation = UUID()
            task?.cancel()
            sending?.cancel()
            timeout?.cancel()
            work?.cancel()
            playbackWatch?.cancel()
            captureWatch?.cancel()
            task = nil
            sending = nil
            timeout = nil
            work = nil
            playbackWatch = nil
            captureWatch = nil
            lastAudioSent = nil
            silentInputSince = nil
            audio?.stop()
            audio = nil
            socket = nil
            network = nil
            wire = nil
            pending = []
            completed = []
            runningCalls = []
            responseOutstanding = false
            flushExchange()
            onExchange = nil
            level = 0
            muted = false
            phase = .idle
            errorKey = nil
            inputWarningKey = nil
            caption = ""
            if closeLive, let previous {
                Task {
                    try? await Self.send(["type": "session.close", "event_id": UUID().uuidString], to: previous)
                    previous.cancel(with: .normalClosure, reason: nil)
                    previousNetwork?.invalidateAndCancel()
                }
            } else {
                previous?.cancel(with: .normalClosure, reason: nil)
                previousNetwork?.invalidateAndCancel()
            }
        }

        private func handle(
            _ event: VoiceProtocol.Event, id: UUID, wire: VoiceProtocol, socket: URLSessionWebSocketTask,
            perform: @escaping (VoiceProtocol.ToolCall) async throws -> String
        ) async throws {
            switch event {
            case .ready:
                guard audio == nil else { return }
                let (stream, continuation) = AsyncStream.makeStream(
                    of: LiveVoiceAudio.Chunk.self, bufferingPolicy: .bufferingNewest(10))
                let audio = LiveVoiceAudio()
                self.audio = audio
                try await audio.start(inputRate: wire.inputRate, capture: !muted, continuation: continuation)
                guard generation == id else {
                    audio.stop()
                    return
                }
                timeout?.cancel()
                try audio.setCaptureEnabled(!muted)
                updatePhase()
                watchCapture(id)
                sending = Task {
                    do {
                        var meteredAt = ContinuousClock.now
                        var needsChime = true
                        for await chunk in stream {
                            guard generation == id, !Task.isCancelled else { return }
                            guard !muted else {
                                silentInputSince = nil
                                inputWarningKey = nil
                                continue
                            }
                            let suppressEcho = audio.suppressSpeakerEcho
                            if suppressEcho || chunk.data.contains(where: { $0 != 0 }) {
                                silentInputSince = nil
                                inputWarningKey = nil
                            } else if let silentInputSince {
                                if silentInputSince.duration(to: .now) >= .seconds(10) {
                                    inputWarningKey = "voice.noInput"
                                }
                            } else if !chunk.data.isEmpty {
                                silentInputSince = .now
                            }
                            let pcm = suppressEcho ? Data(repeating: 0, count: chunk.data.count) : chunk.data
                            try await Self.send(wire.microphone(pcm), to: socket)
                            guard generation == id, !muted else { continue }
                            let first = lastAudioSent == nil
                            lastAudioSent = .now
                            if first {
                                updatePhase()
                                if needsChime {
                                    audio.chime()
                                    needsChime = false
                                }
                            }
                            if phase == .listening, meteredAt.duration(to: .now) >= .milliseconds(70) {
                                level = suppressEcho ? 0 : chunk.level
                                meteredAt = .now
                            }
                        }
                    } catch {
                        if generation == id { fail("voice.connectionFailed") }
                    }
                }
            case .audio(let bytes):
                guard let audio else { return }
                do {
                    let queued = try audio.play(bytes) { [weak self] in
                        guard let self, self.generation == id else { return }
                        self.updatePhase()
                    }
                    if queued { watchPlayback(id) }
                    updatePhase()
                } catch {
                    fail("voice.audioOutputFailed")
                }
            case .interrupted:
                audio?.clearPlayback()
                updatePhase()
            case .turnFinished:
                if !reply.isEmpty { flushExchange() }
            case .cancelTools(let ids):
                pending.removeAll { ids.contains($0.id) }
                if !runningCalls.isDisjoint(with: ids) { work?.cancel() }
            case .turnFailed(let error):
                errorKey = error.key
                audio?.clearPlayback()
                updatePhase()
            case .transcript(let text, let user):
                errorKey = nil
                if user {
                    if !reply.isEmpty { flushExchange() }
                    speech = String((speech + text).suffix(2_000))
                    caption = speech
                } else {
                    reply = String((reply + text).suffix(3_200))
                    caption = reply
                }
            case .tool(let call):
                if !completed.contains(call.id), !pending.contains(where: { $0.id == call.id }), pending.count < 8 {
                    pending.append(call)
                }
            case .toolsReady:
                guard !pending.isEmpty else { return }
                responseOutstanding = true
                execute(wire: wire, socket: socket, id: id, perform: perform)
            case .closed: fail("voice.disconnected")
            case .failure(let error): fail(error.key)
            }
        }

        private func execute(
            wire: VoiceProtocol, socket: URLSessionWebSocketTask, id: UUID,
            perform: @escaping (VoiceProtocol.ToolCall) async throws -> String
        ) {
            guard work == nil, responseOutstanding else { return }
            responseOutstanding = false
            let calls = pending
            pending = []
            runningCalls = Set(calls.map(\.id))
            work = Task {
                defer {
                    if generation == id {
                        work = nil
                        runningCalls = []
                        updatePhase()
                        execute(wire: wire, socket: socket, id: id, perform: perform)
                    }
                }
                do {
                    for call in calls {
                        try Task.checkCancellation()
                        let result: String
                        if completed.contains(call.id) {
                            result = "This call was already handled. Do not repeat it."
                        } else {
                            guard completed.count < 120 else { throw BlueError.invalidValue }
                            completed.insert(call.id)
                            do { result = try await perform(call) } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                let key = (error as? BlueError ?? .saveFailed).key
                                result = Localizer()(key)
                            }
                        }
                        try Task.checkCancellation()
                        try await Self.send(wire.toolOutput(call, result: result), to: socket)
                    }
                    if let command = wire.continueResponse { try await Self.send(command, to: socket) }
                } catch is CancellationError {
                    return
                } catch {
                    if generation == id { fail("voice.connectionFailed") }
                }
            }
            updatePhase()
        }

        private func updatePhase() {
            let next: Phase
            if audio?.playing == true {
                next = .speaking
            } else if work != nil && !Task.isCancelled {
                next = .working
            } else if !muted, lastAudioSent == nil {
                next = .connecting
            } else {
                next = muted ? .muted : .listening
            }
            guard phase != next else { return }
            phase = next
            level = next == .speaking ? 0.6 : 0
        }

        private func watchCapture(_ id: UUID) {
            captureWatch = Task {
                var lastMutedAt = ContinuousClock.now
                while generation == id {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    guard generation == id else { return }
                    if muted {
                        lastMutedAt = .now
                    } else if (lastAudioSent ?? lastMutedAt).duration(to: .now) >= .seconds(3) {
                        fail("voice.captureUnavailable")
                        return
                    }
                }
            }
        }

        private func watchPlayback(_ id: UUID) {
            guard playbackWatch == nil else { return }
            playbackWatch = Task {
                defer { if generation == id { playbackWatch = nil } }
                var previous: AVAudioFramePosition?
                var stalled = 0
                while generation == id, audio?.playing == true {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    guard generation == id, let audio, audio.playing else { return }
                    let position = audio.renderPosition
                    stalled = position != nil && position != previous ? 0 : stalled + 1
                    previous = position
                    if stalled >= 4 {
                        fail("voice.audioOutputFailed")
                        return
                    }
                }
            }
        }

        private func flushExchange() {
            let user = speech.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty { onExchange?(user, answer) }
            speech = ""
            reply = ""
        }

        private func fail(_ key: String) {
            stop()
            errorKey = key
            phase = .failed
        }

        private static func send(_ object: [String: Any], to socket: URLSessionWebSocketTask) async throws {
            let data = try JSONSerialization.data(withJSONObject: object)
            try await socket.send(.string(String(decoding: data, as: UTF8.self)))
        }
    }

    struct VoicePlaybackGate {
        enum Packet { case skip, gap, speech }
        private var gapFrames = 0

        mutating func classify(_ pcm: Data, followingSpeech: Bool) -> Packet {
            let count = pcm.count / 2
            guard count > 0, pcm.count.isMultiple(of: 2) else { return .skip }
            let energy = pcm.withUnsafeBytes { bytes in
                (0..<count).reduce(0.0) { sum, index in
                    let sample = Double(
                        Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)))
                    return sum + sample * sample
                } / Double(count)
            }
            if energy > 90 * 90 {
                gapFrames = 0
                return .speech
            }
            // Preserve short pauses within speech without buffering the provider's idle silence.
            guard followingSpeech, gapFrames + count <= 3_600 else { return .skip }
            gapFrames += count
            return .gap
        }
    }

    private actor LiveAudioSession {
        static let shared = LiveAudioSession()
        private var owner: UUID?

        func activate(_ id: UUID) throws {
            try Task.checkCancellation()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            if session.isEchoCancelledInputAvailable { try? session.setPrefersEchoCancelledInput(true) }
            try session.setActive(true)
            owner = id
            if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
                try session.overrideOutputAudioPort(.speaker)
            }
        }

        func deactivate(_ id: UUID) {
            guard owner == id else { return }
            owner = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    @MainActor
    final class LiveVoiceAudio {
        private final class CaptureProbe: Sendable {
            let rawSignal = Mutex(false)
        }

        struct Chunk: Sendable {
            let data: Data
            let level: Double
        }

        private let engine = AVAudioEngine()
        private let player = AVAudioPlayerNode()
        private let sessionID = UUID()
        private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        private var continuation: AsyncStream<Chunk>.Continuation?
        private var inputRate = 24_000.0
        private var hasTap = false
        private var active = false
        private var buffers = 0
        private var speechBuffers = 0
        private var gate = VoicePlaybackGate()
        private var playbackID = UUID()
        private var echoTailUntil = ContinuousClock.now
        private var captureProbe: CaptureProbe?
        var playing: Bool { speechBuffers > 0 }
        var suppressSpeakerEcho: Bool {
            guard buffers > 0 || ContinuousClock.now < echoTailUntil else { return false }
            let session = AVAudioSession.sharedInstance()
            return !session.isEchoCancelledInputEnabled
                && session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        }
        var renderPosition: AVAudioFramePosition? {
            guard engine.isRunning, player.isPlaying, let time = player.lastRenderTime else { return nil }
            return player.playerTime(forNodeTime: time)?.sampleTime
        }

        func start(
            inputRate: Double, capture: Bool, continuation: AsyncStream<Chunk>.Continuation
        ) async throws {
            self.inputRate = inputRate
            self.continuation = continuation
            do {
                try await LiveAudioSession.shared.activate(sessionID)
                try Task.checkCancellation()
                active = true
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
                engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
                try setCaptureEnabled(capture)
                engine.prepare()
                try engine.start()
            } catch {
                stop()
                await LiveAudioSession.shared.deactivate(sessionID)
                throw error
            }
        }

        func setCaptureEnabled(_ enabled: Bool) throws {
            guard active, enabled != hasTap, let continuation else { return }
            let input = engine.inputNode
            if !enabled {
                input.removeTap(onBus: 0)
                hasTap = false
                return
            }
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0,
                let output = AVAudioFormat(
                    commonFormat: .pcmFormatInt16, sampleRate: inputRate, channels: 1, interleaved: true),
                let converter = AVAudioConverter(from: format, to: output)
            else { throw BlueError.unsupported }
            Self.installTap(
                input, format: format, output: output, converter: converter, continuation: continuation,
                probe: captureProbe)
            hasTap = true
        }

        private nonisolated static func installTap(
            _ input: AVAudioInputNode, format: AVAudioFormat, output: AVAudioFormat, converter: AVAudioConverter,
            continuation: AsyncStream<Chunk>.Continuation, probe: CaptureProbe?
        ) {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                if let probe, let samples = buffer.floatChannelData?[0] {
                    let signal = stride(from: 0, to: Int(buffer.frameLength), by: 8).contains {
                        abs(samples[$0 * buffer.stride]) > 0.000_01
                    }
                    if signal { probe.rawSignal.withLock { $0 = true } }
                }
                let frames =
                    AVAudioFrameCount(ceil(Double(buffer.frameLength) * output.sampleRate / format.sampleRate)) + 16
                guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: frames) else { return }
                var supplied = false
                let status = converter.convert(to: converted, error: nil) { _, state in
                    if supplied {
                        state.pointee = .noDataNow
                        return nil
                    }
                    supplied = true
                    state.pointee = .haveData
                    return buffer
                }
                guard status != .error, converted.frameLength > 0, let samples = converted.int16ChannelData?[0] else {
                    return
                }
                let length = Int(converted.frameLength)
                let level = stride(from: 0, to: length, by: 8).reduce(0.0) { max($0, abs(Double(samples[$1]))) }
                continuation.yield(Chunk(data: Data(bytes: samples, count: length * 2), level: min(1, level / 10_000)))
            }
        }

        func play(_ data: Data, drained: @escaping @MainActor () -> Void) throws -> Bool {
            let count = data.count / 2
            guard count > 0, count <= 72_000 else { return false }
            try recoverEngineIfNeeded()
            let packet = gate.classify(data, followingSpeech: playing)
            guard packet != .skip else { return false }
            guard buffers < 120,
                let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(count)),
                let samples = buffer.floatChannelData?[0]
            else { throw BlueError.unsupported }
            buffer.frameLength = AVAudioFrameCount(count)
            data.withUnsafeBytes { bytes in
                for i in 0..<count {
                    samples[i] = Float(Int16(bitPattern: UInt16(bytes[i * 2]) | UInt16(bytes[i * 2 + 1]) << 8)) / 32768
                }
            }
            let id = playbackID
            buffers += 1
            let voiced = packet == .speech
            if voiced { speechBuffers += 1 }
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.playbackID == id else { return }
                    self.buffers -= 1
                    if self.buffers == 0 { self.echoTailUntil = .now.advanced(by: .milliseconds(120)) }
                    if voiced { self.speechBuffers -= 1 }
                    if !self.playing { drained() }
                }
            }
            if !player.isPlaying { player.play() }
            return voiced
        }

        func chime() {
            let count: AVAudioFrameCount = 4_800
            guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: count),
                let samples = buffer.floatChannelData?[0]
            else { return }
            buffer.frameLength = count
            for i in 0..<Int(count) {
                let t = Double(i) / 24_000
                let envelope = min(1, t / 0.012) * pow(max(0, 1 - t / 0.2), 2)
                samples[i] = Float(0.15 * envelope * (sin(2 * .pi * 520 * t) + 0.5 * sin(2 * .pi * 780 * t)))
            }
            player.scheduleBuffer(buffer)
            echoTailUntil = .now.advanced(by: .milliseconds(250))
            if !player.isPlaying { player.play() }
        }

        func clearPlayback() {
            playbackID = UUID()
            buffers = 0
            speechBuffers = 0
            gate = VoicePlaybackGate()
            player.stop()
        }

        func recoverEngineIfNeeded() throws {
            guard active, !engine.isRunning else { return }
            clearPlayback()
            let capture = hasTap
            try setCaptureEnabled(false)
            try setCaptureEnabled(capture)
            engine.prepare()
            try engine.start()
        }

        func stop() {
            continuation?.finish()
            continuation = nil
            if hasTap { engine.inputNode.removeTap(onBus: 0) }
            hasTap = false
            player.stop()
            engine.stop()
            if active {
                let id = sessionID
                Task { await LiveAudioSession.shared.deactivate(id) }
            }
            active = false
        }

        #if DEBUG
            static func verifyCapture() async {
                guard await AVAudioApplication.requestRecordPermission() else {
                    print("BLUE_VOICE_CAPTURE permission=false")
                    return
                }
                let audio = LiveVoiceAudio()
                let probe = CaptureProbe()
                audio.captureProbe = probe
                let (stream, continuation) = AsyncStream.makeStream(
                    of: Chunk.self, bufferingPolicy: .bufferingNewest(10))
                defer { audio.stop() }
                do {
                    try await audio.start(inputRate: 24_000, capture: true, continuation: continuation)
                    let pcm = (0..<14_400).map { index in
                        let t = Double(index) / 24_000
                        return Int16(9_000 * sin(2 * .pi * 580 * t) * min(1, t * 100, (0.6 - t) * 100))
                    }
                    var drained = false
                    let accepted = try audio.play(pcm.withUnsafeBytes { Data($0) }) { drained = true }
                    let monitor = Task {
                        var packets = 0
                        var frames = 0
                        var hasSignal = false
                        for await chunk in stream {
                            packets += 1
                            frames += chunk.data.count / 2
                            hasSignal = hasSignal || chunk.level > 0
                        }
                        return (packets, frames, hasSignal)
                    }
                    try await Task.sleep(for: .seconds(2))
                    monitor.cancel()
                    let (packets, frames, hasSignal) = await monitor.value
                    let route = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType.rawValue ?? "none"
                    let rawSignal = probe.rawSignal.withLock { $0 }
                    let muted = AVAudioApplication.shared.isInputMuted
                    print(
                        "BLUE_VOICE_CAPTURE packets=\(packets) frames=\(frames) rawSignal=\(rawSignal) signal=\(hasSignal) route=\(route) muted=\(muted) accepted=\(accepted) drained=\(drained)"
                    )
                } catch {
                    let failure = error as NSError
                    print("BLUE_VOICE_CAPTURE failure=\(failure.domain) code=\(failure.code)")
                }
            }

            static func verifyPlayback() async {

                let audio = LiveVoiceAudio()
                let (_, continuation) = AsyncStream.makeStream(of: Chunk.self)
                defer { audio.stop() }
                do {
                    try await audio.start(
                        inputRate: 24_000, capture: false, continuation: continuation)
                    let frames = 9_600
                    let pcm = (0..<frames).map { index in
                        let time = Double(index) / 24_000
                        return Int16(4_500 * sin(2 * .pi * 580 * time) * min(1, time * 100, (0.4 - time) * 100))
                    }
                    var drained = false
                    let accepted = try audio.play(pcm.withUnsafeBytes { Data($0) }) { drained = true }
                    var rendered = false
                    for _ in 0..<30 {
                        try await Task.sleep(for: .milliseconds(50))
                        rendered = rendered || (audio.renderPosition ?? 0) > 0
                        if drained { break }
                    }
                    let route = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "none"
                    print(
                        "BLUE_VOICE_PLAYBACK accepted=\(accepted) rendered=\(rendered) drained=\(drained) route=\(route) engine=\(audio.engine.isRunning) player=\(audio.player.isPlaying) outputVolume=\(AVAudioSession.sharedInstance().outputVolume)"
                    )
                } catch {
                    let failure = error as NSError
                    print("BLUE_VOICE_PLAYBACK failure=\(failure.domain) code=\(failure.code)")
                }
            }
        #endif
    }
#endif
