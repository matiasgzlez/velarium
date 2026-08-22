import AppKit
import ApplicationServices

/// Posts synthetic key events so the phone can drive whatever app is presenting.
/// Requires the Accessibility permission.
enum InputController {

    private static let rightArrow: CGKeyCode = 0x7C
    private static let leftArrow: CGKeyCode  = 0x7B
    private static let escape: CGKeyCode     = 0x35
    private static let equal: CGKeyCode      = 0x18   // '=', que con ⌘ es acercar
    private static let minus: CGKeyCode      = 0x1B
    private static let zero: CGKeyCode       = 0x1D

    static func next() { tap(rightArrow) }
    static func previous() { tap(leftArrow) }
    static func escapeKey() { tap(escape) }

    /// El zoom se lo pedimos a la app de adelante con ⌘+ / ⌘- en vez de ampliar
    /// la captura: la app redibuja a resolución completa, así que no se pierde
    /// nitidez. Anda donde ese atajo existe — PDF, navegadores, Canva — y no
    /// hace nada en Keynote o PowerPoint en modo presentación.
    static func zoomIn()    { tap(equal, flags: .maskCommand) }
    static func zoomOut()   { tap(minus, flags: .maskCommand) }
    static func zoomReset() { tap(zero,  flags: .maskCommand) }

    /// Con la app ampliada hay que poder moverse, y eso es rueda del mouse.
    static func scroll(dx: Int32, dy: Int32) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    /// True once the user has granted Accessibility. `prompt` shows the system dialog.
    @discardableResult
    static func hasAccessibility(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private static func tap(_ key: CGKeyCode, flags: CGEventFlags = []) {
        // .hidSystemState makes the event look like it came from real hardware,
        // which is what apps such as Keynote expect.
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
