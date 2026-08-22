import AppKit

/// La app usa la misma paleta y las mismas formas que la landing, para que abrir
/// Velarium se parezca a la página de la que se descargó: fondo casi blanco,
/// texto casi negro, tipografía redonda y gruesa para los rótulos chicos,
/// tarjetas blancas de borde tenue y botones con forma de píldora.
///
/// Los valores salen de las variables CSS de site/index.html; si cambian allá,
/// cambian acá.
enum Style {

    // MARK: - Paleta

    static let bg       = hex(0xFAFAFA)   // --bg
    static let surface  = hex(0xFFFFFF)   // --surface
    static let sunken   = hex(0xF3F3F3)   // --sunken
    static let border   = hex(0xECECEC)   // --border
    static let text     = hex(0x1A1A1A)   // --text
    static let textSoft = hex(0x3A3A3A)   // --text-soft
    static let solid    = hex(0x2E2E2E)   // --solid
    static let onSolid  = hex(0xFAFAFA)   // --on-solid

    /// El naranja de "falta un permiso". No está en la landing porque la landing
    /// no tiene estados; es lo único que la app suma a la paleta.
    static let warn     = hex(0xB4530A)

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green:   CGFloat((value >> 8)  & 0xFF) / 255,
                blue:    CGFloat( value        & 0xFF) / 255,
                alpha:   1)
    }

    // MARK: - Tipografía

    /// Manrope y Nunito no están en el sistema, así que la app usa el equivalente
    /// de Apple: San Francisco, y su variante redondeada para lo que en la web
    /// va en Nunito.
    static func display(_ size: CGFloat) -> NSFont {
        rounded(size, .heavy)
    }

    static func label(_ size: CGFloat, _ weight: NSFont.Weight = .bold) -> NSFont {
        rounded(size, weight)
    }

    static func body(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    private static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    // MARK: - Formas

    /// Una tarjeta blanca sobre el fondo, como las de la landing.
    static func card(radius: CGFloat = 20) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = surface.cgColor
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 1
        view.layer?.borderColor = border.cgColor
        view.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.09)
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            return shadow
        }()
        return view
    }
}

/// El botón negro con forma de píldora del "Descargar para macOS" de la landing.
final class PillButton: NSButton {

    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.backgroundColor = Style.solid.cgColor
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setLabel(_ text: String) {
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: Style.label(13, .heavy),
            .foregroundColor: Style.onSolid,
        ])
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 40
        size.height += 20
        return size
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
}
