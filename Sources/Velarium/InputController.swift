import AppKit
import ApplicationServices

/// Posts synthetic key events so the phone can drive whatever app is presenting.
/// Requires the Accessibility permission.
enum InputController {

    private static let rightArrow: CGKeyCode = 0x7C
    private static let leftArrow: CGKeyCode  = 0x7B
    private static let escape: CGKeyCode     = 0x35

    static func next() { tap(rightArrow) }
    static func previous() { tap(leftArrow) }
    static func escapeKey() { tap(escape) }

    /// True once the user has granted Accessibility. `prompt` shows the system dialog.
    @discardableResult
    static func hasAccessibility(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private static func tap(_ key: CGKeyCode) {
        // .hidSystemState makes the event look like it came from real hardware,
        // which is what apps such as Keynote expect.
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)?
            .post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?
            .post(tap: .cghidEventTap)
    }
}
