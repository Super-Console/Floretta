import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Official Apple glass for editor chrome that is not the Mac outline or
/// inspector panel plate.
///
/// The Mac outline and the Mac inspector column are a separate change. This
/// file does not draw that panel, and on macOS `inspectorPanel` is a no-op so
/// a second plate is not stacked on top of it. iOS has no such plate yet, so
/// the inspector column uses the path below.
///
/// API, in order:
/// 1. SwiftUI `GlassEffectContainer` + `glassEffect(.regular, in:)`. This is
///    the path the app ships. Deployment is iOS 26 / macOS 26.
/// 2. The runtime-discovered AppKit glass view when a host cannot apply the
///    SwiftUI modifier. `AppleGlassChromePlates` builds it when available.
/// 3. `NSVisualEffectView`, `blendingMode: .behindWindow`. Bars and the
///    inspector plate use material `.sidebar`. Segmented controls, icon
///    buttons, and toolbar buttons use `.underWindowBackground`.
/// 4. On iOS before Liquid Glass, the system control stays as it is. This
///    file does not invent a blur, a frosted fill, or a shadow.
///
/// On iOS, `toolbarFloatingButton` is a no-op. Those controls are already
/// system toolbar items, which supply official glass and a circular hit
/// target. Wrapping them in `GlassEffectContainer` turns the bar into custom
/// content: the back button's accessibility frame shrinks to the chevron
/// (~20pt), and `editor.more` can drop out of the bar.
///
/// Contrast. Chrome labels and SF Symbols use `.foregroundStyle(.primary)`.
/// In the light appearance that ink is dark. In the dark appearance it is
/// light. The same call is used for both. This file does not branch on the
/// current appearance, and it does not paint a white or black wash under the label.
/// Inspector form text keeps the system label styles, which follow the same
/// light and dark appearances. Screenshots of both appearances are left for
/// a later Mac pass. This environment cannot render the app.
enum AppleGlassChromeRole: String, Equatable {
    /// iOS inspector column. macOS returns the content unchanged.
    case inspectorPanel
    /// The 样式 / 演说 / 导图 segmented control.
    case segmentedContainer
    /// Icon buttons, including the inspector empty-state brush.
    case iconButton
    /// Capsule bars, including the bottom sheet capsules.
    case bottomBarCapsule
    /// Toolbar buttons that float over the canvas. Not the back button.
    /// On iOS this is a no-op; the system toolbar item already has official glass.
    case toolbarFloatingButton
}

enum AppleGlassChromeBackend: String, Equatable {
    case swiftUIGlassEffect
    case nsGlassEffectView
    case nsVisualEffectView
    /// iOS without the glass control. No substitute blur is drawn.
    case unpainted

    static var resolved: AppleGlassChromeBackend {
        #if os(macOS)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return .swiftUIGlassEffect
        }
        #endif
        return .nsGlassEffectView
        #else
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            return .swiftUIGlassEffect
        }
        #endif
        return .unpainted
        #endif
    }
}

enum AppleGlassChromeMetrics {
    static let panelCornerRadius: CGFloat = 16
}

extension View {
    /// One official glass plate for a single chrome surface.
    func appleGlassChrome(_ role: AppleGlassChromeRole) -> some View {
        AppleGlassChromePlate(role: role) { self }
    }

    /// Lets the iOS inspector glass show through the form. Does not restyle
    /// the form's pickers, sliders, or toggles. macOS is unchanged here; the
    /// Mac panel plate is not this modifier.
    @ViewBuilder
    func appleGlassInspectorFormPlate() -> some View {
        #if os(iOS)
        self.scrollContentBackground(.hidden)
        #else
        self
        #endif
    }
}

private struct AppleGlassChromePlate<Content: View>: View {
    var role: AppleGlassChromeRole
    var content: Content

    init(role: AppleGlassChromeRole, @ViewBuilder content: () -> Content) {
        self.role = role
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        if role == .inspectorPanel {
            content
        } else {
            hosted(content)
        }
        #else
        if role == .toolbarFloatingButton {
            content
        } else {
            hosted(content)
        }
        #endif
    }

    @ViewBuilder
    private func hosted<V: View>(_ view: V) -> some View {
        switch role {
        case .iconButton:
            plated(inked(view), shape: Circle())
        case .segmentedContainer, .bottomBarCapsule, .toolbarFloatingButton:
            plated(inked(view), shape: Capsule())
        case .inspectorPanel:
            plated(inked(view), shape: RoundedRectangle(cornerRadius: AppleGlassChromeMetrics.panelCornerRadius, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("inspector.panel.glass")
        }
    }

    @ViewBuilder
    private func inked<V: View>(_ view: V) -> some View {
        switch role {
        case .inspectorPanel:
            view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .iconButton:
            view.symbolRenderingMode(.monochrome).foregroundStyle(.primary)
        case .toolbarFloatingButton, .segmentedContainer, .bottomBarCapsule:
            view.foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func plated<V: View, S: Shape>(_ view: V, shape: S) -> some View {
        switch AppleGlassChromeBackend.resolved {
        case .swiftUIGlassEffect:
            #if compiler(>=6.2)
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: CGFloat(0)) {
                    view.glassEffect(.regular, in: shape)
                }
            } else {
                degraded(view, shape: shape)
            }
            #else
            degraded(view, shape: shape)
            #endif
        case .nsGlassEffectView:
            #if os(macOS)
            view.background { AppleGlassChromeAppKitPlate(role: role) }
                .clipShape(shape)
            #else
            degraded(view, shape: shape)
            #endif
        case .nsVisualEffectView:
            degraded(view, shape: shape)
        case .unpainted:
            view
        }
    }

    @ViewBuilder
    private func degraded<V: View, S: Shape>(_ view: V, shape: S) -> some View {
        #if os(macOS)
        view.background { AppleGlassChromeVisualPlate(role: role) }
            .clipShape(shape)
        #else
        view
        #endif
    }
}

#if os(macOS)
extension AppleGlassChromeRole {
    var fallbackMaterial: NSVisualEffectView.Material {
        switch self {
        case .bottomBarCapsule, .inspectorPanel:
            .sidebar
        case .segmentedContainer, .iconButton, .toolbarFloatingButton:
            .underWindowBackground
        }
    }

    var plateCornerRadius: CGFloat {
        switch self {
        case .inspectorPanel:
            AppleGlassChromeMetrics.panelCornerRadius
        case .iconButton:
            22
        case .segmentedContainer, .bottomBarCapsule, .toolbarFloatingButton:
            20
        }
    }
}

@MainActor
enum AppleGlassChromePlates {
    // Resolve by name because older macOS SDKs do not declare this AppKit type.
    static let glassEffectClass: AnyClass? = NSClassFromString("NSGlassEffectView")

    /// Uses the system glass view when present; otherwise keeps the chrome readable
    /// with AppKit's system vibrancy material.
    static func makeGlassEffectView(role: AppleGlassChromeRole, cornerRadius: CGFloat) -> NSView {
        if let viewClass = glassEffectClass as? NSView.Type {
            let view = viewClass.init(frame: .zero)
            view.setValue(cornerRadius, forKey: "cornerRadius")
            return view
        }

        return makeVisualEffectView(role: role, cornerRadius: cornerRadius)
    }

    /// Last-resort system material. Does not paint a white or gray fill.
    static func makeVisualEffectView(role: AppleGlassChromeRole, cornerRadius: CGFloat) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        updateVisualEffectView(view, role: role, cornerRadius: cornerRadius)
        return view
    }

    static func updateVisualEffectView(_ view: NSVisualEffectView, role: AppleGlassChromeRole, cornerRadius: CGFloat) {
        view.material = role.fallbackMaterial
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        view.layer?.backgroundColor = nil
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

@MainActor
private struct AppleGlassChromeAppKitPlate: NSViewRepresentable {
    var role: AppleGlassChromeRole

    func makeNSView(context: Context) -> NSView {
        AppleGlassChromePlates.makeGlassEffectView(role: role, cornerRadius: role.plateCornerRadius)
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let visualEffectView = view as? NSVisualEffectView {
            AppleGlassChromePlates.updateVisualEffectView(visualEffectView, role: role, cornerRadius: role.plateCornerRadius)
        } else {
            view.setValue(role.plateCornerRadius, forKey: "cornerRadius")
        }
    }
}

@MainActor
private struct AppleGlassChromeVisualPlate: NSViewRepresentable {
    var role: AppleGlassChromeRole

    func makeNSView(context: Context) -> NSVisualEffectView {
        AppleGlassChromePlates.makeVisualEffectView(role: role, cornerRadius: role.plateCornerRadius)
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = role.fallbackMaterial
        view.blendingMode = .behindWindow
        view.layer?.cornerRadius = role.plateCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = nil
    }
}
#endif
