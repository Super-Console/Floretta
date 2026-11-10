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
/// 2. AppKit `NSGlassEffectView` (`.regular`) when a host cannot apply the
///    SwiftUI modifier but the macOS 26 class exists. `AppleGlassChromePlates`
///    builds that view.
/// 3. `NSVisualEffectView`, `blendingMode: .behindWindow`. Bars and the
///    inspector plate use material `.sidebar`. Segmented controls, icon
///    buttons, and toolbar buttons use `.underWindowBackground`.
/// 4. On iOS before Liquid Glass, the system control stays as it is. This
///    file does not invent a blur, a frosted fill, or a shadow.
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
        if #available(macOS 26.0, *) {
            return .swiftUIGlassEffect
        }
        return .nsVisualEffectView
        #else
        if #available(iOS 26.0, *) {
            return .swiftUIGlassEffect
        }
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
        hosted(content)
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
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: CGFloat(0)) {
                    view.glassEffect(.regular, in: shape)
                }
            } else {
                degraded(view, shape: shape)
            }
        case .nsGlassEffectView:
            #if os(macOS)
            if #available(macOS 26.0, *) {
                view.background { AppleGlassChromeAppKitPlate(role: role) }
                    .clipShape(shape)
            } else {
                degraded(view, shape: shape)
            }
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
    /// AppKit glass plate. Tests and the `nsGlassEffectView` backend use this.
    @available(macOS 26.0, *)
    static func makeGlassEffectView(cornerRadius: CGFloat) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.style = .regular
        return view
    }

    /// Last-resort system material. Does not paint a white or gray fill.
    static func makeVisualEffectView(role: AppleGlassChromeRole, cornerRadius: CGFloat) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = role.fallbackMaterial
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

@available(macOS 26.0, *)
@MainActor
private struct AppleGlassChromeAppKitPlate: NSViewRepresentable {
    var role: AppleGlassChromeRole

    func makeNSView(context: Context) -> NSGlassEffectView {
        AppleGlassChromePlates.makeGlassEffectView(cornerRadius: role.plateCornerRadius)
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = role.plateCornerRadius
        view.style = .regular
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
