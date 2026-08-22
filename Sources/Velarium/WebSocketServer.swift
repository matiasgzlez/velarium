import Foundation
import Network

/// Carries screen frames down to the phone and control commands back up.
/// Network.framework handles the RFC 6455 handshake and framing for us.
final class WebSocketServer {

    /// A command the phone sent us.
    enum Command {
        case next
        case previous
        case escape
        case zoom(scale: Double, x: Double, y: Double)
        case pan(dx: Double, dy: Double)
        case zoomEnded
        case selectDisplay(id: UInt32)
        case switchApp
        case fullScreen
        case nextTab
        case prevTab
        case nextWindow
        case selectWindow(pid: pid_t, windowID: UInt32, title: String)
        case requestWindows
        case laser(active: Bool, x: Double, y: Double)
    }

    private(set) var boundPort: UInt16 = 0
    private let token: String
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.velarium.ws")

    var onCommand: ((Command) -> Void)?
    var onClientCountChanged: ((Int) -> Void)?
    var onClientAuthenticated: (() -> Void)?
    var onReady: ((UInt16) -> Void)?
    var onFailure: ((String) -> Void)?

    private final class Client {
        let connection: NWConnection
        var authenticated = false
        /// Permite hasta 2 cuadros en vuelo para lograr 60 FPS continuos sin parates.
        var inFlight = 0
        var sentAt = Date.distantPast
        var stalled: Bool { inFlight > 0 && Date().timeIntervalSince(sentAt) > 1 }
        init(_ connection: NWConnection) { self.connection = connection }
    }

    private var clients: [ObjectIdentifier: Client] = [:]

    init(token: String) {
        self.token = token
    }

    var clientCount: Int {
        queue.sync { clients.values.filter(\.authenticated).count }
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(options, at: 0)

        let listener = try NWListener(using: params, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let port = self.listener?.port?.rawValue ?? 0
                self.boundPort = port
                DispatchQueue.main.async { self.onReady?(port) }
            case .failed(let error):
                DispatchQueue.main.async { self.onFailure?(error.localizedDescription) }
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            self?.clients.values.forEach { $0.connection.cancel() }
            self?.clients.removeAll()
        }
    }

    // MARK: - Connections

    func accept(_ connection: NWConnection) {
        let client = Client(connection)
        queue.async { self.clients[ObjectIdentifier(connection)] = client }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.remove(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: client)
    }

    private func remove(_ connection: NWConnection) {
        queue.async {
            guard self.clients.removeValue(forKey: ObjectIdentifier(connection)) != nil else { return }
            let count = self.clients.values.filter(\.authenticated).count
            DispatchQueue.main.async { self.onClientCountChanged?(count) }
        }
    }

    private func receive(on client: Client) {
        client.connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if error != nil { client.connection.cancel(); return }

            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata {
                if metadata.opcode == .close {
                    client.connection.cancel()
                    return
                }
                if metadata.opcode == .text, let data {
                    self.handle(text: data, from: client)
                }
            }
            self.receive(on: client)
        }
    }

    private func handle(text: Data, from client: Client) {
        guard let json = try? JSONSerialization.jsonObject(with: text) as? [String: Any],
              let kind = json["t"] as? String else { return }

        // Nothing but the handshake is honoured until the QR token checks out.
        guard client.authenticated else {
            if kind == "auth", let given = json["token"] as? String, given == token {
                client.authenticated = true
                let count = clients.values.filter(\.authenticated).count
                DispatchQueue.main.async {
                    self.onClientCountChanged?(count)
                    self.onClientAuthenticated?()
                }
            } else {
                client.connection.cancel()
            }
            return
        }

        if kind == "ack" {
            if client.inFlight > 0 { client.inFlight -= 1 }
            return
        }

        let command: Command?
        switch kind {
        case "next": command = .next
        case "prev": command = .previous
        case "esc":  command = .escape
        case "switchApp": command = .switchApp
        case "fullscreen": command = .fullScreen
        case "nextTab": command = .nextTab
        case "prevTab": command = .prevTab
        case "nextWindow": command = .nextWindow
        case "laser":
            let active = json["active"] as? Bool ?? false
            let x = json["x"] as? Double ?? 0.5
            let y = json["y"] as? Double ?? 0.5
            command = .laser(active: active, x: x, y: y)
        case "requestWindows": command = .requestWindows
        case "selectWindow":
            let pid = json["pid"] as? Int32 ?? 0
            let windowID = json["windowID"] as? UInt32 ?? 0
            let title = json["title"] as? String ?? ""
            command = .selectWindow(pid: pid, windowID: windowID, title: title)
        case "selectDisplay":
            if let idNum = json["id"] as? UInt32 {
                command = .selectDisplay(id: idNum)
            } else if let idInt = json["id"] as? Int {
                command = .selectDisplay(id: UInt32(idInt))
            } else {
                command = nil
            }
        case "zoom":
            let scale = json["scale"] as? Double ?? 1
            let x = json["x"] as? Double ?? 0.5
            let y = json["y"] as? Double ?? 0.5
            command = .zoom(scale: scale, x: x, y: y)
        case "pan":
            command = .pan(dx: json["dx"] as? Double ?? 0, dy: json["dy"] as? Double ?? 0)
        case "zoomEnd": command = .zoomEnded
        default: command = nil
        }
        if let command {
            DispatchQueue.main.async { self.onCommand?(command) }
        }
    }

    // MARK: - Sending

    /// Pushes a JPEG to every connected phone.
    /// Multi-buffered streaming up to 3 frames in flight ensures smooth 120fps movement.
    func broadcast(frame: Data) {
        queue.async {
            for client in self.clients.values where client.authenticated && (client.inFlight < 3 || client.stalled) {
                if client.stalled { client.inFlight = 0 }
                client.inFlight += 1
                client.sentAt = Date()
                let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
                let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
                client.connection.send(content: frame,
                                       contentContext: context,
                                       isComplete: true,
                                       completion: .contentProcessed { [weak self, weak client] error in
                                           if error != nil {
                                               self?.queue.async {
                                                   if let client { client.inFlight = max(0, client.inFlight - 1) }
                                               }
                                           }
                                       })
            }
        }
    }

    func broadcast(json object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        queue.async {
            for client in self.clients.values where client.authenticated {
                let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
                let context = NWConnection.ContentContext(identifier: "json", metadata: [metadata])
                client.connection.send(content: data,
                                       contentContext: context,
                                       isComplete: true,
                                       completion: .contentProcessed { _ in })
            }
        }
    }
}
