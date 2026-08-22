import AppKit

struct LaserPoint {
    let point: CGPoint
    let timestamp: Date
}

/// Dibuja un puntero láser brillante con estela bézier suave sobre la pantalla de la Mac.
final class LaserPointer {
    static let shared = LaserPointer()

    private var window: NSPanel?
    private var laserView: LaserCanvasView?
    private var timer: Timer?

    private final class LaserCanvasView: NSView {
        var points: [LaserPoint] = []

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }

            let now = Date()
            let validDuration: TimeInterval = 1.0
            points.removeAll { now.timeIntervalSince($0.timestamp) > validDuration }

            guard !points.isEmpty else { return }

            // 1. Dibujar la estela láser con curvas bézier ultra suaves
            if points.count > 1 {
                ctx.saveGState()
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)

                let path = CGMutablePath()
                path.move(to: points[0].point)

                if points.count == 2 {
                    path.addLine(to: points[1].point)
                } else {
                    for i in 1..<points.count - 1 {
                        let p1 = points[i].point
                        let p2 = points[i + 1].point
                        let mid = CGPoint(x: (p1.x + p2.x) / 2.0, y: (p1.y + p2.y) / 2.0)
                        path.addQuadCurve(to: mid, control: p1)
                    }
                    if let last = points.last {
                        path.addLine(to: last.point)
                    }
                }

                // Resplandor exterior (Glow aura)
                ctx.addPath(path)
                ctx.setStrokeColor(NSColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 0.3).cgColor)
                ctx.setLineWidth(18.0)
                ctx.strokePath()

                // Núcleo rojo incandescente
                ctx.addPath(path)
                ctx.setStrokeColor(NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.9).cgColor)
                ctx.setLineWidth(8.0)
                ctx.strokePath()

                // Centro blanco brillante
                ctx.addPath(path)
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
                ctx.setLineWidth(3.0)
                ctx.strokePath()

                ctx.restoreGState()
            }

            // 2. Dibujar la cabeza del láser (Punto activo)
            if let last = points.last {
                let center = last.point
                ctx.saveGState()

                // Glow exterior
                ctx.setFillColor(NSColor.red.withAlphaComponent(0.35).cgColor)
                ctx.fillEllipse(in: CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44))

                // Punto rojo brillante
                ctx.setFillColor(NSColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 0.95).cgColor)
                ctx.fillEllipse(in: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22))

                // Núcleo blanco incandescente
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                ctx.restoreGState()
            }
        }
    }

    func update(active: Bool, x: Double = 0.5, y: Double = 0.5, displayID: CGDirectDisplayID? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let screen = NSScreen.screens.first { screen in
                let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                return id == displayID
            } ?? NSScreen.main ?? NSScreen.screens.first

            guard let screenFrame = screen?.frame else { return }

            if self.window == nil || self.window?.frame != screenFrame {
                self.window?.orderOut(nil)
                let win = NSPanel(contentRect: screenFrame,
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered,
                                  defer: false)
                win.backgroundColor = .clear
                win.isOpaque = false
                win.hasShadow = false
                win.level = .floating
                win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                win.ignoresMouseEvents = true

                let view = LaserCanvasView(frame: NSRect(origin: .zero, size: screenFrame.size))
                win.contentView = view

                self.window = win
                self.laserView = view
            }

            if !active {
                self.laserView?.points.removeAll()
                self.laserView?.needsDisplay = true
                self.stopTimer()
                self.window?.orderOut(nil)
                return
            }

            let ptX = CGFloat(x) * screenFrame.width
            let ptY = screenFrame.height * (1.0 - CGFloat(y))
            let newPt = LaserPoint(point: CGPoint(x: ptX, y: ptY), timestamp: Date())

            self.laserView?.points.append(newPt)
            self.laserView?.needsDisplay = true
            self.window?.orderFront(nil)

            self.startTimer()
        }
    }

    private func startTimer() {
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                guard let self, let view = self.laserView else { return }
                view.needsDisplay = true
                if view.points.isEmpty {
                    self.stopTimer()
                    self.window?.orderOut(nil)
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
