import AppKit

/// Uses the real Liquid Glass material on macOS 26 and a native vibrancy
/// material on earlier supported systems.
@MainActor
final class GlassSurfaceView: NSView {
    private let embeddedContent: NSView
    private let glassCornerRadius: CGFloat
    private let tintColor: NSColor?
    private var surfaceView: NSView?

    init(
        contentView: NSView,
        cornerRadius: CGFloat = 16,
        tintColor: NSColor? = NSColor.controlAccentColor.withAlphaComponent(0.10)
    ) {
        self.embeddedContent = contentView
        self.glassCornerRadius = cornerRadius
        self.tintColor = tintColor
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        buildSurface()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard surfaceView != nil else { return }
        buildSurface()
    }

    private func buildSurface() {
        embeddedContent.removeFromSuperview()
        surfaceView?.removeFromSuperview()

        let surface: NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let solidView = NSView()
            solidView.wantsLayer = true
            solidView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            solidView.layer?.cornerRadius = glassCornerRadius
            solidView.addSubview(embeddedContent)
            surface = solidView
        } else if #available(macOS 26.0, *),
                  let glassView = Self.makeNativeGlassView(
                    contentView: embeddedContent,
                    cornerRadius: glassCornerRadius,
                    tintColor: tintColor
                  ) {
            surface = glassView
        } else {
            let effectView = NSVisualEffectView()
            effectView.material = .popover
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = glassCornerRadius
            effectView.layer?.masksToBounds = true
            effectView.addSubview(embeddedContent)
            surface = effectView
        }

        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        embeddedContent.frame = surface.bounds
        embeddedContent.autoresizingMask = [.width, .height]
        addSubview(surface)
        surfaceView = surface
    }

    @objc private func displayOptionsDidChange() {
        buildSurface()
    }

    /// `NSGlassEffectView` is loaded dynamically so release builds remain
    /// reproducible with either the macOS 15 or macOS 26 SDK. On macOS 26 the
    /// resulting object is still Apple's native Liquid Glass view; older
    /// systems take the `NSVisualEffectView` path above.
    private static func makeNativeGlassView(
        contentView: NSView,
        cornerRadius: CGFloat,
        tintColor: NSColor?
    ) -> NSView? {
        guard let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type else {
            return nil
        }

        let glassView = glassType.init(frame: .zero)
        guard glassView.responds(to: NSSelectorFromString("setContentView:")),
              glassView.responds(to: NSSelectorFromString("setCornerRadius:")),
              glassView.responds(to: NSSelectorFromString("setTintColor:")),
              glassView.responds(to: NSSelectorFromString("setStyle:")) else {
            return nil
        }

        glassView.setValue(contentView, forKey: "contentView")
        glassView.setValue(cornerRadius, forKey: "cornerRadius")
        glassView.setValue(tintColor, forKey: "tintColor")
        glassView.setValue(0, forKey: "style") // NSGlassEffectViewStyleRegular
        return glassView
    }
}
