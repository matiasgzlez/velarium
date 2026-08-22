import Foundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreGraphics

struct CapturedFrame {
    /// Downscaled JPEG for the phone.
    let jpeg: Data
    /// Native-resolution image, used by the zoom overlay so magnifying stays sharp.
    let full: CGImage
}

/// Captures one display and emits a frame only when the screen actually changed.
/// Slides are static most of the time, so this keeps bandwidth near zero.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {

    var onFrame: ((CapturedFrame) -> Void)?
    var onStopped: ((String) -> Void)?

    /// Width sent to the phone. Slides stay legible well below native resolution.
    var previewWidth = 1100
    var jpegQuality: CGFloat = 0.55

    private var stream: SCStream?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let outputQueue = DispatchQueue(label: "app.velarium.capture", qos: .userInitiated)
    private let encodeQueue = DispatchQueue(label: "app.velarium.encode", qos: .userInitiated)
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

    func start(displayID: CGDirectDisplayID? = nil) async throws {
        await stop()

        let content = try await shareableContent()
        displays = content.displays
        guard let display = displays.first(where: { $0.displayID == displayID }) ?? displays.first else {
            throw NSError(domain: "Velarium", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "No se encontró ninguna pantalla"])
        }
        activeDisplayID = display.displayID

        // ScreenCaptureKit no respeta `NSWindow.sharingType`: si no lo excluimos
        // acá, el overlay de zoom se captura a sí mismo y se realimenta — zoom
        // del zoom, que en pantalla se ve como un temblor que va perdiendo
        // calidad. Se excluye Velarium entera, así tampoco viaja al celular la
        // ventana del QR.
        let ourApp = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ourApp,
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()

        // Cap the capture so a 5K display doesn't cost more GPU than the job needs,
        // while still leaving headroom for the zoom overlay to magnify into.
        let maxWidth = 2560
        let scale = min(1.0, Double(maxWidth) / Double(display.width))
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        // 20fps is imperceptible on slides and leaves headroom on a congested
        // lecture-hall network. Static slides send nothing at all.
        config.minimumFrameInterval = CMTime(value: 1, timescale: 20)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        config.capturesAudio = false

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

        // `.complete` means new pixels; `.idle` means the screen is unchanged and
        // ScreenCaptureKit is just keeping the stream alive. Only the former is worth sending.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        stateLock.lock()
        if encoding { stateLock.unlock(); return }
        encoding = true
        stateLock.unlock()

        // Render to a CGImage synchronously: ScreenCaptureKit recycles its IOSurfaces,
        // so the pixel buffer must not outlive this callback.
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        guard let full = ciContext.createCGImage(source, from: source.extent) else {
            stateLock.lock(); encoding = false; stateLock.unlock()
            return
        }

        encodeQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.stateLock.lock()
                self.encoding = false
                self.stateLock.unlock()
            }
            guard let jpeg = self.encode(full) else { return }
            self.onFrame?(CapturedFrame(jpeg: jpeg, full: full))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        DispatchQueue.main.async { self.onStopped?(error.localizedDescription) }
    }

    private func encode(_ image: CGImage) -> Data? {
        let scale = min(1.0, Double(previewWidth) / Double(image.width))
        let ci = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.jpegRepresentation(
            of: ci,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality]
        )
    }
}
