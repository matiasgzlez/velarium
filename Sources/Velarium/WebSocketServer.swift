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
    }

    private(set) var boundPort: UInt16 = 0
    private let token: String
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.velarium.ws")

    var onCommand: ((Command) -> Void)?
    var onClientCountChanged: ((Int) -> Void)?
    var onReady: ((UInt16) -> Void)?
    var onFailure: ((String) -> Void)?

    private final class Client {
        let connection: NWConnection
        var authenticated = false
        /// Frames are dropped rather than queued while one is still going out,
        /// so a slow phone falls behind in quality, never in latency.
        var sending = false
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

    private func accept(_ connection: NWConnection) {
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
                DispatchQueue.main.async { self.onClientCountChanged?(count) }
            } else {
                client.connection.cancel()
            }
            return
        }

        let command: Command?
        switch kind {
        case "next": command = .next
        case "prev": command = .previous
        case "esc":  command = .escape
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

    /// Pushes a JPEG to every connected phone, skipping any that is still busy.
    func broadcast(frame: Data) {
        queue.async {
            for client in self.clients.values where client.authenticated && !client.sending {
                client.sending = true
                let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
                let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
                client.connection.send(content: frame,
                                       contentContext: context,
                                       isComplete: true,
                                       completion: .contentProcessed { _ in
                    self.queue.async { client.sending = false }
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
