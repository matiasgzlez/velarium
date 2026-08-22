import Foundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreGraphics

struct CapturedFrame {
    /// JPEG codificado en alta definición para el dispositivo cliente.
    let jpeg: Data
}

/// Captura una pantalla a hasta 60 FPS con cero retardo cuando hay movimiento.
/// Las diapositivas estáticas no emiten cuadros cuando no hay cambios.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {

    var onFrame: ((CapturedFrame) -> Void)?
    var onStopped: ((String) -> Void)?

    /// Ancho máximo enviado al dispositivo (2880px preserva nitidez nativa Retina).
    var previewWidth = 2880
    /// Calidad JPEG al 88% (ultra-rápido para 120 FPS y nitidez impecable).
    var jpegQuality: CGFloat = 0.88

    private var stream: SCStream?
    private let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .priorityRequestLow: false
    ])
    private let outputQueue = DispatchQueue(label: "app.velarium.capture", qos: .userInteractive)
    private let encodeQueue = DispatchQueue(label: "app.velarium.encode", qos: .userInteractive)
    private let stateLock = NSLock()
    private var encoding = false

    private(set) var displays: [SCDisplay] = []
    private(set) var activeDisplayID: CGDirectDisplayID?

    /// Screen Recording is the one permission we cannot work around.
    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    func refreshDisplays() async throws -> [SCDisplay] {
        displays = try await shareableContent().displays
        return displays
    }

    private func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    }

    func getOpenWindows() async throws -> [[String: Any]] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let ourBundleID = Bundle.main.bundleIdentifier
        var results: [[String: Any]] = []

        for window in content.windows {
            guard let app = window.owningApplication,
                  app.bundleIdentifier != ourBundleID,
                  let title = window.title, !title.isEmpty,
                  window.windowLayer <= 5,
                  window.frame.width > 150, window.frame.height > 150
            else { continue }

            results.append([
                "id": window.windowID,
                "pid": app.processID,
                "appName": app.applicationName,
                "title": title
            ])
        }
        return results
    }

    func start(displayID: CGDirectDisplayID? = nil) async throws {
        await stop()

        let content = try await shareableContent()
        displays = content.displays
        guard let display = displays.first(where: { $0.displayID == displayID }) ?? displays.first else {
            throw NSError(domain: "Velarium", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "No se encontró ninguna pantalla"])
        }
        activeDisplayID = display.displayID

        let ourApp = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ourApp,
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()

        let maxWidth = 2880
        let scale = min(1.0, Double(maxWidth) / Double(display.width))
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        // 120 FPS para movimiento ultra fluido ProMotion (120Hz en iPad Pro)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        config.queueDepth = 8
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        config.capturesAudio = false

        FileHandle.standardError.write(Data("[cap] display=\(display.width)x\(display.height) config=\(config.width)x\(config.height) q=\(jpegQuality) fps=120\n".utf8))
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        stateLock.lock()
        if encoding { stateLock.unlock(); return }
        encoding = true
        stateLock.unlock()

        let source = CIImage(cvPixelBuffer: pixelBuffer)

        encodeQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.stateLock.lock()
                self.encoding = false
                self.stateLock.unlock()
            }
            guard let jpeg = self.encode(source) else { return }
            self.onFrame?(CapturedFrame(jpeg: jpeg))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        DispatchQueue.main.async { self.onStopped?(error.localizedDescription) }
    }

    private func encode(_ source: CIImage) -> Data? {
        let currentWidth = source.extent.width
        let scale = min(1.0, Double(previewWidth) / Double(currentWidth))
        let ci: CIImage
        if scale < 0.99 {
            ci = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        } else {
            ci = source
        }
        return ciContext.jpegRepresentation(
            of: ci,
            colorSpace: sRGBColorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality]
        )
    }
}
