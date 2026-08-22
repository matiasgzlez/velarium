import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Posts synthetic key events so the phone can drive whatever app is presenting.
/// Requires the Accessibility permission.
enum InputController {

    private static let rightArrow: CGKeyCode = 0x7C
    private static let leftArrow: CGKeyCode  = 0x7B
    private static let escape: CGKeyCode     = 0x35
    private static let tabKey: CGKeyCode     = 0x30
    private static let fKey: CGKeyCode       = 0x03
    private static let backtickKey: CGKeyCode = 0x32

    static func next() { tap(rightArrow) }
    static func previous() { tap(leftArrow) }
    static func escapeKey() { tap(escape) }
    static func switchApp() { tap(tabKey, flags: .maskCommand) }
    static func fullScreen() { tap(fKey, flags: [.maskControl, .maskCommand]) }
    static func nextTab() { tap(tabKey, flags: .maskControl) }
    static func prevTab() { tap(tabKey, flags: [.maskControl, .maskShift]) }
    static func nextWindow() { tap(backtickKey, flags: .maskCommand) }

    /// Eleva al frente la ventana específica indicada por título y PID, permitiendo
    /// cambiar entre múltiples archivos/ventanas de la misma aplicación (ej. varios PDFs en Vista Previa).
    static func bringWindowToFront(pid: pid_t, title: String) {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }

        guard !title.isEmpty else { return }

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        if result == .success, let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let windowTitle = titleRef as? String {
                    if windowTitle == title || windowTitle.contains(title) || title.contains(windowTitle) {
                        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                        break
                    }
                }
            }
        }
    }

    /// El zoom se lo pedimos a la app de adelante con ⌘+ / ⌘- en vez de ampliar
    /// la captura: la app redibuja a resolución completa, así que no se pierde
    /// nitidez. Anda donde ese atajo existe — PDF, navegadores, Canva — y no
    /// hace nada en Keynote o PowerPoint en modo presentación.
    static func zoomIn()    { type("+") ?? type("=") }
    static func zoomOut()   { type("-") }
    static func zoomReset() { type("0") }

    /// Manda ⌘ junto al carácter pedido.
    ///
    /// Los keycodes son posiciones físicas, no caracteres: `0x18` es la tecla que
    /// da `=` en un teclado US y otra cosa en uno español. Hardcodearlos hacía que
    /// el atajo llegara como ⌘ más una tecla cualquiera. Se resuelve la posición
    /// contra el layout activo.
    @discardableResult
    private static func type(_ character: Character) -> Void? {
        guard let (code, needsShift) = keyPosition(of: character) else { return nil }
        tap(code, flags: needsShift ? [.maskCommand, .maskShift] : .maskCommand)
        return ()
    }

    /// Recorre el layout de teclado activo buscando qué tecla produce el carácter.
    private static func keyPosition(of character: Character) -> (CGKeyCode, Bool)? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        return data.withUnsafeBytes { buffer -> (CGKeyCode, Bool)? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return nil }

            // Sin Shift primero: si el carácter está en las dos, preferimos la simple.
            for shift in [false, true] {
                let modifiers = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
                for code in 0..<CGKeyCode(128) {
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown),
                                                modifiers, keyboardType,
                                                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                                &deadKeys, characters.count, &length, &characters)
                    guard status == noErr, length == 1,
                          let scalar = UnicodeScalar(characters[0]) else { continue }
                    if Character(scalar) == character { return (code, shift) }
                }
            }
            return nil
        }
    }

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
