import AppKit
import Network
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()

    private var http: HTTPServer!
    private var sockets: WebSocketServer!
    private let capturer = ScreenCapturer()
    private let overlay = ZoomOverlay()
    private let pathMonitor = NWPathMonitor()

    // UI
    private let qrView = NSImageView()
    private let urlLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Iniciando…")
    private let hintLabel = NSTextField(labelWithString: "")
    private let displayPicker = NSPopUpButton()
    private let permissionButton = NSButton(title: "", target: nil, action: nil)

    private var connectedPhones = 0
    private var framesSent = 0
    private var statusItem: NSStatusItem?
    private var knownScreenCount = NSScreen.screens.count

    /// Goes to stderr so `Velarium.app/Contents/MacOS/Velarium` in a terminal
    /// tells you what is happening when something does not connect.
    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[velarium] \(message)\n".utf8))
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        buildStatusItem()
        startServers()
        watchNetwork()
        watchDisplays()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window parks Velarium in the menu bar so it is still there
    /// when you plug into the projector later.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.hide()
        http?.stop()
        sockets?.stop()
    }

    // MARK: - Window

    private func buildWindow() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 620))

        let title = NSTextField(labelWithString: "Velarium")
        title.font = .systemFont(ofSize: 26, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Escaneá con la cámara del celular")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        qrView.imageScaling = .scaleProportionallyUpOrDown
        qrView.wantsLayer = true
        qrView.layer?.backgroundColor = NSColor.white.cgColor
        qrView.layer?.cornerRadius = 12

        urlLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.alignment = .center
        urlLabel.isSelectable = true

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.alignment = .center

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.maximumNumberOfLines = 3
        hintLabel.lineBreakMode = .byWordWrapping

        displayPicker.target = self
        displayPicker.action = #selector(displayChanged)
        displayPicker.isHidden = true

        permissionButton.target = self
        permissionButton.action = #selector(permissionTapped)
        permissionButton.bezelStyle = .rounded
        permissionButton.isHidden = true

        let stack = NSStackView(views: [
            title, subtitle, qrView, urlLabel, statusLabel, permissionButton, displayPicker, hintLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(14, after: qrView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -48),
            qrView.widthAnchor.constraint(equalToConstant: 260),
            qrView.heightAnchor.constraint(equalToConstant: 260),
            hintLabel.widthAnchor.constraint(equalToConstant: 360),
        ])

        window = NSWindow(contentRect: content.frame,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        window.title = "Velarium"
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled",
                                     accessibilityDescription: "Velarium")

        let menu = NSMenu()
        let show = NSMenuItem(title: "Mostrar el QR", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        // Left targetless on purpose so it walks the responder chain up to NSApp.
        menu.addItem(NSMenuItem(title: "Salir de Velarium",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Displays

    private func watchDisplays() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    /// Plugging in HDMI is the moment you need Velarium, so that is when it shows up.
    @objc private func screensChanged() {
        let count = NSScreen.screens.count
        let gained = count > knownScreenCount
        knownScreenCount = count
        log("pantallas: \(count)\(gained ? " (se conectó una)" : "")")

        // Whatever happened, the projector is the display worth mirroring now.
        Task { @MainActor in
            guard let displays = try? await capturer.refreshDisplays() else { return }
            buildDisplayPicker(displays)
            if let target = preferredDisplay(among: displays), target != capturer.activeDisplayID {
                overlay.hide()
                try? await capturer.start(displayID: target)
                log("cambiado a la pantalla \(target)")
            }
            if gained { announceProjector() }
        }
    }

    private func announceProjector() {
        showWindow()
        statusLabel.stringValue = "Proyector detectado — escaneá para controlarlo"
        statusLabel.textColor = .systemGreen
        refreshQR()
    }

    // MARK: - Servers

    /// Los archivos web viven en distinto lugar según cómo arranque el proceso:
    /// dentro del .app quedan en Contents/Resources, y con `swift run` SwiftPM
    /// deja su bundle de recursos al lado del binario. `Bundle.module` sólo
    /// contempla lo segundo, y ante la duda aborta el proceso en vez de devolver
    /// nil — por eso lo resolvemos a mano y podemos avisar en pantalla.
    private static func locateWebRoot() -> URL? {
        let bundle = "Velarium_Velarium.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Web"),
            Bundle.main.resourceURL?.appendingPathComponent(bundle).appendingPathComponent("Web"),
            Bundle.main.bundleURL.appendingPathComponent(bundle).appendingPathComponent("Web"),
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private func startServers() {
        guard let webRoot = Self.locateWebRoot() else {
            statusLabel.stringValue = "No se encontraron los archivos web"
            return
        }

        sockets = WebSocketServer(token: String(token))
        http = HTTPServer(webRoot: webRoot, token: String(token))

        sockets.onCommand = { [weak self] in self?.handle($0) }
        sockets.onClientCountChanged = { [weak self] count in
            self?.connectedPhones = count
            self?.refreshStatus()
        }
        sockets.onFailure = { [weak self] message in
            self?.statusLabel.stringValue = "Error de red: \(message)"
        }

        // The page needs the socket port baked in, so HTTP waits for the socket.
        sockets.onReady = { [weak self] wsPort in
            guard let self else { return }
            self.http.wsPort = wsPort
            self.http.onReady = { [weak self] port in
                self?.log("servidor listo — http:\(port) ws:\(wsPort)")
                self?.refreshQR()
                self?.beginCapture()
            }
            try? self.http.start()
        }

        do {
            try sockets.start()
        } catch {
            statusLabel.stringValue = "No se pudo abrir el servidor: \(error.localizedDescription)"
        }
    }

    private func watchNetwork() {
        // Switching to a phone hotspot changes our IP, which invalidates the QR.
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.refreshQR() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "app.velarium.path"))
    }

    private func refreshQR() {
        guard (http?.boundPort ?? 0) != 0 else { return }
        guard let interface = NetworkInfo.primary else {
            qrView.image = nil
            urlLabel.stringValue = ""
            statusLabel.stringValue = "Sin red"
            hintLabel.stringValue = "Conectá la Mac a una red Wi-Fi, o prendé el hotspot del celular y conectá la Mac ahí."
            return
        }

        let url = "http://\(interface.address):\(http.boundPort)/?t=\(token)"
        qrView.image = QRCode.image(for: url, size: 520)
        urlLabel.stringValue = "\(url.replacingOccurrences(of: "?t=\(token)", with: ""))  ·  \(interface.label)"
        refreshStatus()
    }

    private func refreshStatus() {
        if connectedPhones > 0 {
            statusLabel.stringValue = "● Celular conectado"
            statusLabel.textColor = .systemGreen
            hintLabel.stringValue = "Deslizá para cambiar de diapositiva. Pellizcá para hacer zoom."
        } else {
            statusLabel.stringValue = "Esperando el celular…"
            statusLabel.textColor = .secondaryLabelColor
            hintLabel.stringValue = "La Mac y el celular tienen que estar en la misma red. Si el Wi-Fi de la facultad los aísla, usá el hotspot del celular."
        }
    }

    // MARK: - Capture

    private func beginCapture() {
        log("permisos — pantalla: \(ScreenCapturer.hasPermission()), accesibilidad: \(InputController.hasAccessibility())")
        guard ScreenCapturer.hasPermission() else {
            showPermission(title: "Permitir grabación de pantalla",
                           hint: "Velarium necesita ver tu pantalla para retransmitirla al celular.")
            return
        }
        guard InputController.hasAccessibility() else {
            showPermission(title: "Permitir accesibilidad",
                           hint: "Velarium necesita este permiso para pasar las diapositivas por vos.")
            return
        }
        permissionButton.isHidden = true

        capturer.onFrame = { [weak self] frame in
            guard let self else { return }
            self.sockets.broadcast(frame: frame.jpeg)
            self.framesSent += 1
            if self.framesSent % 100 == 1 { self.log("frames enviados: \(self.framesSent)") }
            guard self.overlay.isActive else { return }
            DispatchQueue.main.async { self.overlay.present(frame.full) }
        }
        capturer.onStopped = { [weak self] message in
            self?.statusLabel.stringValue = "Captura detenida: \(message)"
        }

        Task { @MainActor in
            do {
                let displays = try await capturer.refreshDisplays()
                buildDisplayPicker(displays)
                try await capturer.start(displayID: preferredDisplay(among: displays))
                log("capturando pantalla \(capturer.activeDisplayID ?? 0) de \(displays.count) disponible(s)")
                refreshStatus()
            } catch {
                log("error de captura: \(error.localizedDescription)")
                statusLabel.stringValue = "No se pudo capturar: \(error.localizedDescription)"
            }
        }
    }

    /// When a projector is plugged in, that is almost always what you want to mirror.
    private func preferredDisplay(among displays: [SCDisplay]) -> CGDirectDisplayID? {
        let builtIn = CGMainDisplayID()
        if displays.count > 1, let external = displays.first(where: { $0.displayID != builtIn }) {
            return external.displayID
        }
        return displays.first?.displayID
    }

    private func buildDisplayPicker(_ displays: [SCDisplay]) {
        guard displays.count > 1 else { displayPicker.isHidden = true; return }
        displayPicker.removeAllItems()
        for (index, display) in displays.enumerated() {
            let isMain = display.displayID == CGMainDisplayID()
            displayPicker.addItem(withTitle: isMain
                ? "Pantalla \(index + 1) (principal)"
                : "Pantalla \(index + 1) — \(display.width)×\(display.height)")
            displayPicker.lastItem?.tag = Int(display.displayID)
        }
        if let preferred = preferredDisplay(among: displays) {
            displayPicker.selectItem(withTag: Int(preferred))
        }
        displayPicker.isHidden = false
    }

    @objc private func displayChanged() {
        let id = CGDirectDisplayID(displayPicker.selectedTag())
        overlay.hide()
        Task { try? await capturer.start(displayID: id) }
    }

    // MARK: - Permissions

    private func showPermission(title: String, hint: String) {
        permissionButton.title = title
        permissionButton.isHidden = false
        statusLabel.stringValue = "Falta un permiso"
        statusLabel.textColor = .systemOrange
        hintLabel.stringValue = hint
    }

    @objc private func permissionTapped() {
        if !ScreenCapturer.hasPermission() {
            ScreenCapturer.requestPermission()
        } else if !InputController.hasAccessibility() {
            InputController.hasAccessibility(prompt: true)
        }
        // The grant lands asynchronously, so re-check shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.beginCapture()
        }
    }

    // MARK: - Commands from the phone

    private func handle(_ command: WebSocketServer.Command) {
        switch command {
        case .next:
            InputController.next()
        case .previous:
            InputController.previous()
        case .escape:
            InputController.escapeKey()
        case .zoom(let scale, let x, let y):
            if scale <= 1.01 {
                overlay.hide()
            } else {
                overlay.show(on: capturer.activeDisplayID)
                overlay.update(scale: CGFloat(scale), x: CGFloat(x), y: CGFloat(y))
            }
        case .zoomEnded:
            overlay.hide()
        }
    }
}
