import Foundation
import FoundationModels
import Network

// The simulator's model catalog can be unavailable while the Mac model works.
// Only this development harness listens on loopback. No device/Release app uses it.
@MainActor final class AlarmService {
    func alarms(on date: Date) -> [SavedAlarm] { [] }
    func save(_ alarm: SavedAlarm) async throws { throw BlueError.unsupported }
}

@MainActor final class ModelBridgeServer {
    let token: String
    private var listener: NWListener?
    private var buffers: [UUID: Data] = [:]
    init(token: String) { self.token = token }
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 7977)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let id = UUID()
                self.buffers[id] = Data()
                connection.start(queue: .global(qos: .userInitiated))
                self.receive(connection, id: id)
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        print("Blue local model bridge listening on 127.0.0.1:7977; availability: \(SystemLanguageModel.default.availability)")
    }
    private func receive(_ connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, done, error in
            Task { @MainActor in
                if let data { self.buffers[id, default: Data()].append(data) }
                guard let buffer = self.buffers[id], buffer.count <= 8_001_000, error == nil else {
                    self.buffers[id] = nil; connection.cancel(); return
                }
                if let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let header = String(decoding: buffer[..<boundary.lowerBound], as: UTF8.self)
                    let lines = header.components(separatedBy: "\r\n")
                    guard lines.first?.hasPrefix("POST /respond HTTP/1.") == true,
                        lines.contains(where: { $0.lowercased().hasPrefix("authorization:") && $0.dropFirst(14).trimmingCharacters(in: .whitespaces) == "Bearer " + self.token }),
                        let lengthLine = lines.first(where: { $0.lowercased().hasPrefix("content-length:") }),
                        let length = Int(lengthLine.dropFirst(15).trimmingCharacters(in: .whitespaces)), length > 0, length <= 8_000_000 else {
                        self.buffers[id] = nil; self.reply(connection, code: 403, body: Data()); return
                    }
                    if buffer.count - boundary.upperBound >= length {
                        self.buffers[id] = nil
                        let body = Data(buffer[boundary.upperBound..<(boundary.upperBound + length)])
                        await self.respond(connection, body: body)
                        return
                    }
                }
                if done { self.buffers[id] = nil; connection.cancel() }
                else { self.receive(connection, id: id) }
            }
        }
    }
    private func respond(_ connection: NWConnection, body: Data) async {
        do {
            let request = try JSONDecoder().decode(ModelBridgeRequest.self, from: body)
            guard request.prompt.count <= 2000 else { throw BlueError.invalidValue }
            let store = try LibraryStore(inMemory: true, seed: false)
            try store.update { $0 = request.library }
            let assistant = AssistantService()
            assistant.selectSurface(request.surface ?? "all", day: request.selectedDay)
            if let id = request.collectionID { assistant.selectCollection(id, store: store) }
            if let id = request.previousRecord { assistant.selectRecord(id) }
            if let id = request.noteID { assistant.selectNote(id) }
            if let id = request.eventID { assistant.selectEvent(id) }
            assistant.input = request.prompt
            assistant.submit(store: store, alarms: AlarmService(), language: request.language)
            let deadline = ContinuousClock.now.advanced(by: .seconds(85))
            var lastState = ""
            while assistant.busy {
                if lastState != assistant.state.rawValue {
                    lastState = assistant.state.rawValue
                    FileHandle.standardError.write(Data("MODEL_PHASE=\(lastState)\n".utf8))
                }
                if ContinuousClock.now > deadline { assistant.cancel(); throw BlueError.cancelled }
                try await Task.sleep(for: .milliseconds(60))
            }
            let response = ModelBridgeResponse(library: store.state, result: assistant.result ?? .message("assistant.clarify"))
            reply(connection, code: 200, body: try JSONEncoder().encode(response))
        } catch { FileHandle.standardError.write(Data("MODEL_REQUEST_FAILED=\(type(of: error))\n".utf8)); reply(connection, code: 500, body: Data()) }
    }
    private func reply(_ connection: NWConnection, code: Int, body: Data) {
        let header = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

@main struct MacModelBridge {
    @MainActor static func main() async {
        guard let token = ProcessInfo.processInfo.environment["BLUE_MODEL_BRIDGE_TOKEN"], token.count >= 32 else { exit(1) }
        do {
            let server = ModelBridgeServer(token: token)
            try server.start()
            while !Task.isCancelled { try await Task.sleep(for: .seconds(30)) }
        } catch { print("Local model bridge could not start."); exit(1) }
    }
}
