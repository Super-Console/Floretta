import SwiftUI
#if os(macOS)
import AppKit

/// Official Apple glass for the Mac outline (left) and inspector (right).
///
/// Deployment target is macOS 26.0 (`MACOSX_DEPLOYMENT_TARGET` in the app
/// target). The panels therefore call SwiftUI `glassEffect(_:in:)` inside a
/// `GlassEffectContainer`. That modifier is the material; this file does not
/// draw a blur, a translucent white fill, or a shadow.
///
/// Degradation, in order:
/// 1. SwiftUI `glassEffect(.regular, in:)` — used when the view can host the
///    modifier. These panels are SwiftUI, so this is the path they ship.
/// 2. AppKit `NSGlassEffectView` — used when a container cannot host the
///    SwiftUI modifier but the macOS 26 AppKit class is present. Pass
///    `AppleGlassBackend.nsGlassEffectView`. The same factory is what the
///    unit test instantiates.
/// 3. `NSVisualEffectView` with `material: .underWindowBackground` and
///    `blendingMode: .behindWindow` — used when neither Liquid Glass API
///    exists (deployment target or OS older than macOS 26). Corners use the
///    system continuous corner curve. No fill color is painted on top.
enum AppleGlassMetrics {
    /// Continuous corner radius, in the 12–16pt range of the window corners.
    static let cornerRadius: CGFloat = 16
    /// Inset so the rounded glass sits inside the window instead of flush to a hard edge.
    static let panelInset: CGFloat = 12
    static let outlineWidth: CGFloat = 300
    static let inspectorWidth: CGFloat = 320
}

enum AppleGlassBackend: String, Equatable {
    case swiftUIGlassEffect
    case nsGlassEffectView
    case nsVisualEffectView

    /// What the editor panels install.
    ///
    /// macOS 26 SwiftUI views take `swiftUIGlassEffect`. `nsGlassEffectView` is
    /// the AppKit plate for a host that cannot apply the modifier; ask for it
    /// with `AppleGlassBackend.nsGlassEffectView`. Below macOS 26 neither
    /// Liquid Glass type exists, so the plate is `nsVisualEffectView`.
    static var resolved: AppleGlassBackend {
        if #available(macOS 26.0, *) {
            return .swiftUIGlassEffect
        }
        return .nsVisualEffectView
    }
}

struct AppleGlassPanel<Content: View>: View {
    var backend: AppleGlassBackend
    var cornerRadius: CGFloat
    private var content: Content

    init(
        backend: AppleGlassBackend = .resolved,
        cornerRadius: CGFloat = AppleGlassMetrics.cornerRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.backend = backend
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        glass
            .accessibilityIdentifier("appleGlass.\(backend.rawValue)")
    }

    @ViewBuilder
    private var glass: some View {
        if backend == .swiftUIGlassEffect {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: CGFloat(0)) {
                    content.appleGlassEffect(cornerRadius: cornerRadius, backend: .swiftUIGlassEffect)
                }
            } else {
                content.appleGlassEffect(cornerRadius: cornerRadius, backend: .nsVisualEffectView)
            }
        } else {
            content.appleGlassEffect(cornerRadius: cornerRadius, backend: backend)
        }
    }
}

extension View {
    /// One official glass plate behind this view. No solid fill, no shadow.
    @ViewBuilder
    func appleGlassEffect(
        cornerRadius: CGFloat = AppleGlassMetrics.cornerRadius,
        backend: AppleGlassBackend = .resolved
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch backend {
        case .swiftUIGlassEffect:
            if #available(macOS 26.0, *) {
                self.clipShape(shape)
                    .glassEffect(.regular, in: shape)
            } else {
                self.background { VisualEffectGlassPlate(cornerRadius: cornerRadius) }
                    .clipShape(shape)
            }
        case .nsGlassEffectView:
            if #available(macOS 26.0, *) {
                self.background { AppKitGlassPlate(cornerRadius: cornerRadius) }
                    .clipShape(shape)
            } else {
                self.background { VisualEffectGlassPlate(cornerRadius: cornerRadius) }
                    .clipShape(shape)
            }
        case .nsVisualEffectView:
            self.background { VisualEffectGlassPlate(cornerRadius: cornerRadius) }
                .clipShape(shape)
        }
    }
}

@available(macOS 26.0, *)
@MainActor
enum AppleGlassPlate {
    /// The AppKit view the fallback path installs. Tests construct this directly.
    static func makeGlassEffectView(cornerRadius: CGFloat) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.style = .regular
        return view
    }
}

@available(macOS 26.0, *)
@MainActor
private struct AppKitGlassPlate: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        AppleGlassPlate.makeGlassEffectView(cornerRadius: cornerRadius)
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.style = .regular
    }
}

@MainActor
enum AppleGlassVisualEffectPlate {
    /// Last-resort system material. Does not paint a white or gray fill.
    static func makeView(cornerRadius: CGFloat) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        view.layer?.backgroundColor = nil
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }
}

@MainActor
private struct VisualEffectGlassPlate: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        AppleGlassVisualEffectPlate.makeView(cornerRadius: cornerRadius)
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
    }
}

#if DEBUG
private struct AppleGlassPanelPreview: PreviewProvider {
    static var previews: some View {
        Group {
            sample.preferredColorScheme(.light).previewDisplayName("Glass light")
            sample.preferredColorScheme(.dark).previewDisplayName("Glass dark")
        }
    }

    private static var sample: some View {
        ZStack {
            LinearGradient(
                colors: [.mint, .orange, .indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack {
                AppleGlassPanel {
                    Text(verbatim: "大纲")
                        .frame(width: 240, height: 360)
                }
                Spacer()
                AppleGlassPanel {
                    Text(verbatim: "检查器")
                        .frame(width: 260, height: 360)
                }
            }
            .padding(16)
        }
        .frame(width: 840, height: 560)
    }
}
#endif
#endif
