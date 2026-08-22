import Foundation
import Network

/// Serves the phone-side web app over the LAN. Deliberately tiny: GET only,
/// no keep-alive, no directory traversal.
final class HTTPServer {

    /// Port the phone connects to. Known only once the listener is ready.
    private(set) var boundPort: UInt16 = 0
    /// Injected into index.html so the page knows where its socket lives.
    var wsPort: UInt16 = 0
    var onReady: ((UInt16) -> Void)?
    var onFailure: ((String) -> Void)?

    private let webRoot: URL
    private let token: String
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.velarium.http")

    init(webRoot: URL, token: String) {
        self.webRoot = webRoot
        self.token = token
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Port 0 lets the OS hand us a free one, so we never collide with
        // whatever else the user happens to be running.
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
    }

    // MARK: - Request handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard error == nil else { connection.cancel(); return }

            var buffer = buffer
            if let data { buffer.append(data) }

            // Headers end at the blank line; we never read a body because we only accept GET.
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
                return
            }
            if isComplete || buffer.count > 64 * 1024 { connection.cancel(); return }
            self.read(connection, buffer: buffer)
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        guard let requestLine = head.split(separator: "\r\n").first else {
            return send(status: "400 Bad Request", body: Data(), type: "text/plain", on: connection)
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return send(status: "405 Method Not Allowed", body: Data(), type: "text/plain", on: connection)
        }

        // Strip the query string; the token only matters to the WebSocket.
        let rawPath = String(parts[1])
        let path = String(rawPath.split(separator: "?").first ?? "/")
        let name = (path == "/" || path.isEmpty) ? "index.html" : String(path.dropFirst())

        // Flat web root, so anything with a slash or a dot-dot is a probe.
        guard !name.contains("/"), !name.contains("..") else {
            return send(status: "403 Forbidden", body: Data(), type: "text/plain", on: connection)
        }

        let file = webRoot.appendingPathComponent(name)
        guard var body = try? Data(contentsOf: file) else {
            return send(status: "404 Not Found", body: Data("no encontrado".utf8), type: "text/plain", on: connection)
        }

        // The page needs to know where to open the socket and how to authenticate.
        if name == "index.html" {
            var html = String(decoding: body, as: UTF8.self)
            html = html.replacingOccurrences(of: "__WS_PORT__", with: String(wsPort))
            html = html.replacingOccurrences(of: "__TOKEN__", with: token)
            body = Data(html.utf8)
        }

        send(status: "200 OK", body: body, type: Self.contentType(for: name), on: connection)
    }

    private func send(status: String, body: Data, type: String, on connection: NWConnection) {
        let headers = """
        HTTP/1.1 \(status)\r
        Content-Type: \(type)\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var response = Data(headers.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func contentType(for name: String) -> String {
        if name.hasSuffix(".html") { return "text/html; charset=utf-8" }
        if name.hasSuffix(".js")   { return "application/javascript; charset=utf-8" }
        if name.hasSuffix(".css")  { return "text/css; charset=utf-8" }
        if name.hasSuffix(".svg")  { return "image/svg+xml" }
        if name.hasSuffix(".png")  { return "image/png" }
        return "application/octet-stream"
    }
}
