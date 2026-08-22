import AppKit

/// A click-through window that covers the display and shows a magnified copy of it.
///
/// We already hold every frame at native resolution, so magnifying is just a matter
/// of drawing the latest one scaled and offset. Keeping this window out of the capture
/// is what stops it from magnifying its own output, and that exclusion lives in
/// `ScreenCapturer.start()`: ScreenCaptureKit ignores `sharingType`, so the filter has
/// to exclude the app. `sharingType = .none` below only covers screenshots and sharing.
final class ZoomOverlay {

    private var window: NSWindow?
    private let layer = CALayer()
    private var scale: CGFloat = 1
    private var focus = CGPoint(x: 0.5, y: 0.5)

    /// Readable from the capture thread, which must not touch NSWindow.
    private let activeLock = NSLock()
    private var active = false
    var isActive: Bool {
        activeLock.lock(); defer { activeLock.unlock() }
        return active
    }

    private func setActive(_ value: Bool) {
        activeLock.lock(); active = value; activeLock.unlock()
    }

    // MARK: - Lifecycle

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.hasShadow = false
        // Above full-screen slideshows, and never part of what we capture.
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let host = NSView(frame: screen.frame)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        layer.frame = host.bounds
        layer.contentsGravity = .resizeAspect
        layer.magnificationFilter = .linear
        host.layer?.addSublayer(layer)
        window.contentView = host
        return window
    }

    /// The display we magnify has to be the one we capture, not wherever the mouse is.
    private func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return NSScreen.main }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        } ?? NSScreen.main
    }

    // MARK: - Control

    func show(on displayID: CGDirectDisplayID?) {
        guard window == nil, let screen = screen(for: displayID) else { return }
        let window = makeWindow(on: screen)
        self.window = window
        window.orderFrontRegardless()
        setActive(true)
    }

    func hide() {
        setActive(false)
        window?.orderOut(nil)
        window = nil
        scale = 1
    }

    /// `x` and `y` are normalised to the captured image, origin top-left.
    func update(scale: CGFloat, x: CGFloat, y: CGFloat) {
        self.scale = max(1, scale)
        self.focus = CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        applyTransform()
    }

    func present(_ image: CGImage) {
        guard window != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit fade between frames
        layer.contents = image
        applyTransform()
        CATransaction.commit()
    }

    private func applyTransform() {
        guard let bounds = window?.contentView?.bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Scale about the focus point, then clamp so the magnified image never
        // exposes an empty edge.
        let maxOffsetX = bounds.width * (scale - 1) / 2
        let maxOffsetY = bounds.height * (scale - 1) / 2
        let wantX = (0.5 - focus.x) * bounds.width * scale
        // CoreAnimation's Y grows upward; the phone sends it growing downward.
        let wantY = (focus.y - 0.5) * bounds.height * scale

        layer.frame = bounds
        layer.transform = CATransform3DConcat(
            CATransform3DMakeScale(scale, scale, 1),
            CATransform3DMakeTranslation(
                min(max(wantX, -maxOffsetX), maxOffsetX),
                min(max(wantY, -maxOffsetY), maxOffsetY),
                0)
        )
        CATransaction.commit()
    }
}
