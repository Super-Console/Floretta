import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// Official Apple glass for shell and editor chrome.
///
/// On macOS `inspectorPanel` is a no-op so a second plate is not stacked on
/// the system inspector column, which already provides Liquid Glass. The
/// iOS inspector, both platforms' sidebars, and the editor outline column
/// use the path below. `sidebarColumn` is the shared token for the iPad
/// home sidebar, the Mac home sidebar, and the editor outline.
///
/// Two official implementations are kept side by side and selected by
/// `GlassChromeConfiguration.renderingStyle` (default `.light`):
/// - `.light` is the shipped "frosted" Liquid Glass: `GlassEffectContainer`
///   + `glassEffect(.regular.tint(_:), in:)`, with a system `Material`
///   underlay that diffuses the background into color blocks and a soft
///   bottom-edge fade instead of a hard cut.
/// - `.native` is the system vibrancy material: `NSVisualEffectView`
///   (macOS) / `UIVisualEffectView` (iOS) with a scene-specific material
///   (`.sidebar` / `.headerView` / `.hudWindow`) and a matching
///   `blendingMode`.
///
/// API, in order for the `.light` path:
/// 1. SwiftUI `GlassEffectContainer` + `glassEffect(_:in:)`. Deployment is
///    iOS 26 / macOS 26. The thin tint is applied through Apple's
///    `Glass.tint(_:)`; no semi-transparent colour is painted by hand.
/// 2. The runtime-discovered AppKit glass view when a host cannot apply the
///    SwiftUI modifier. `AppleGlassChromePlates` builds it when available.
/// 3. `NSVisualEffectView` as the older-OS fallback. The blending mode is the
///    sample source, and it follows the role, not habit: chrome that floats
///    over the canvas (`bottomBarCapsule`, `floatingPanel`) blurs the window's
///    own content (`blendingMode: .withinWindow`, material `.hudWindow` /
///    `.popover`), so a node passing under a plate is diffused instead of
///    showing through with a sharp edge that reads as a cut-off bar.
///    Columns (`sidebarColumn`, `inspectorPanel`) keep
///    `blendingMode: .behindWindow` with material `.sidebar`: they own a
///    column of the window and are supposed to sample the window backdrop.
///    Segmented controls, icon buttons, and toolbar buttons use
///    `.underWindowBackground`.
/// 4. On iOS before Liquid Glass, the system control stays as it is. This
///    file does not invent a blur, a frosted fill, or a shadow.
///
/// `toolbarFloatingButton` draws no plate on either platform. Those controls
/// are system toolbar items, and the system already paints the official glass
/// capsule behind them. A second plate inside the item is the double-glass
/// bug: a faint capsule inside the system one, most visible on macOS. Pressed
/// and hover states stay the system's, so nothing has to be painted back to
/// keep the feedback. On iOS, wrapping them in `GlassEffectContainer` also
/// turns the bar into custom content: the back button's accessibility frame
/// shrinks to the chevron (~20pt), and `editor.more` can drop out of the bar.
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
    /// The 样式 / 导图 segmented control.
    case segmentedContainer
    /// Icon buttons, including the inspector empty-state brush.
    case iconButton
    /// Capsule bars, including the bottom sheet capsules.
    case bottomBarCapsule
    /// Toolbar buttons that float over the canvas. Not the back button.
    /// Draws no plate on either platform: a system toolbar item already paints
    /// Apple's official glass capsule behind its content, and a second plate
    /// inside the item is the double-glass bug (a faint capsule inside the
    /// system one, most visible on macOS). A button that is *not* in a toolbar
    /// uses `canvasFloatingButton`.
    case toolbarFloatingButton
    /// A button that floats directly over the canvas, outside any toolbar: the
    /// Zen exit. It needs its own plate, because nothing else supplies glass
    /// there.
    case canvasFloatingButton
    /// NavigationSplitView sidebar and the editor outline column.
    case sidebarColumn
    /// Floating banners, status strips, and the in-canvas audio bar.
    case floatingPanel
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

/// A/B switch between the two official glass implementations.
/// `.light` (default) is the refined frosted Liquid Glass; `.native` is the
/// system vibrancy material path. Both implementations stay in this file.
/// Change the constant below and rebuild to compare them on both platforms.
enum GlassRenderingStyle: String, CaseIterable, Equatable {
    case light
    case native
}

enum GlassChromeConfiguration {
    /// Switch location for A/B: set to `.native` for the system-material
    /// implementation, `.light` for the default frosted implementation.
    static let renderingStyle: GlassRenderingStyle = .light
}

/// The three system scenes the `.native` path maps to an Apple material.
enum GlassNativeScene {
    case sidebar
    case header
    case hud
}

enum AppleGlassChromeMetrics {
    static let panelCornerRadius: CGFloat = 16
    static let sidebarCornerRadius: CGFloat = 24
    /// Thin tint for the `.light` glass, applied through `Glass.tint(_:)`.
    /// It lowers the contrast of content behind the glass so dark text and
    /// borders no longer read as a "reflection". This is an official glass
    /// tint, not a hand-filled semi-transparent overlay.
    static let lightTint = Color.primary.opacity(0.12)
    /// Height of the soft bottom-edge fade on glass bands. A gradient alpha
    /// mask only; it does not draw a blur or a colour fill.
    static let glassBandBottomFadeHeight: CGFloat = 18
    /// Horizontal inset that keeps the sidebar's selected-row capsule clear
    /// of the column's rounded edge, so the two arcs never collide.
    static let sidebarRowInset: CGFloat = 8
}

extension AppleGlassChromeRole {
    /// Whether this role draws its own plate here.
    ///
    /// A toolbar item is already glass: the system paints the capsule and the
    /// hit target, and a plate inside it shows as a second capsule. The macOS
    /// inspector column is already Liquid Glass for the same reason. Both are
    /// answered here, so no call site has to remember it.
    var drawsPlate: Bool {
        switch self {
        case .toolbarFloatingButton:
            return false
        case .inspectorPanel:
            #if os(macOS)
            return false
            #else
            return true
            #endif
        case .segmentedContainer, .iconButton, .bottomBarCapsule, .sidebarColumn, .floatingPanel, .canvasFloatingButton:
            return true
        }
    }

    /// Chrome that floats over canvas content instead of owning a column of
    /// the window: the two bottom capsules, the in-canvas banners and audio
    /// bar. A plate over content has to blur that content; a plate over the
    /// window backdrop has to blur the backdrop. One property answers which,
    /// so no plate re-decides it on its own.
    var floatsOverContent: Bool {
        switch self {
        case .bottomBarCapsule, .floatingPanel, .canvasFloatingButton:
            return true
        case .inspectorPanel, .sidebarColumn, .segmentedContainer, .iconButton, .toolbarFloatingButton:
            return false
        }
    }

    /// Underlay material for the `.light` path. A plate over the canvas gets
    /// the thicker material, so a node under it stops reading as a sharp
    /// shape; the columns and in-bar controls keep the thin one.
    var lightUnderlayMaterial: Material {
        floatsOverContent ? .thickMaterial : .thinMaterial
    }

    /// Chrome that reads as a horizontal band over the canvas; its bottom
    /// edge fades out instead of ending in a hard cut.
    var fadesBottomEdge: Bool {
        switch self {
        case .floatingPanel, .segmentedContainer, .bottomBarCapsule, .canvasFloatingButton:
            return true
        case .inspectorPanel, .sidebarColumn, .iconButton, .toolbarFloatingButton:
            return false
        }
    }

    /// Scene used to pick the `.native` system material on both platforms.
    var nativeScene: GlassNativeScene {
        switch self {
        case .sidebarColumn, .inspectorPanel:
            return .sidebar
        case .segmentedContainer, .iconButton, .toolbarFloatingButton:
            return .header
        case .floatingPanel, .bottomBarCapsule, .canvasFloatingButton:
            return .hud
        }
    }
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

    /// Soft bottom-edge fade for a glass band. Uses only an alpha gradient
    /// mask (opaque -> clear): no custom blur, no semi-transparent colour
    /// fill, and the glass itself stays an official Apple material.
    @ViewBuilder
    func glassBandBottomFade(_ height: CGFloat, enabled: Bool) -> some View {
        if enabled {
            self.modifier(GlassBandBottomFadeModifier(fadeHeight: height))
        } else {
            self
        }
    }

    /// Keep the native sidebar selection inset while leaving selection drawing
    /// to `List(.sidebar)`; a custom row background would layer a second shape.
    func sidebarSelectionInset() -> some View {
        let inset = AppleGlassChromeMetrics.sidebarRowInset
        return self
            .listRowInsets(EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset))
            .listRowBackground(Color.clear)
    }
}

private struct GlassBandBottomFadeModifier: ViewModifier {
    var fadeHeight: CGFloat

    func body(content: Content) -> some View {
        content.mask {
            VStack(spacing: 0) {
                Rectangle().fill(Color.black)
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }
        }
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
        if role.drawsPlate {
            hosted(content)
        } else {
            content
        }
    }

    @ViewBuilder
    private func hosted<V: View>(_ view: V) -> some View {
        switch role {
        case .iconButton:
            plated(inked(view), shape: Circle())
        case .segmentedContainer, .bottomBarCapsule, .toolbarFloatingButton, .canvasFloatingButton:
            plated(inked(view), shape: Capsule())
        case .inspectorPanel:
            plated(inked(view), shape: RoundedRectangle(cornerRadius: AppleGlassChromeMetrics.panelCornerRadius, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("inspector.panel.glass")
        case .sidebarColumn:
            plated(inked(view), shape: RoundedRectangle(cornerRadius: AppleGlassChromeMetrics.sidebarCornerRadius, style: .continuous))
        case .floatingPanel:
            plated(inked(view), shape: RoundedRectangle(cornerRadius: AppleGlassChromeMetrics.panelCornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func inked<V: View>(_ view: V) -> some View {
        switch role {
        case .inspectorPanel, .sidebarColumn:
            view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .floatingPanel:
            view
        case .iconButton:
            view.symbolRenderingMode(.monochrome).foregroundStyle(.primary)
        case .toolbarFloatingButton, .segmentedContainer, .bottomBarCapsule, .canvasFloatingButton:
            view.foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func plated<V: View, S: Shape>(_ view: V, shape: S) -> some View {
        switch GlassChromeConfiguration.renderingStyle {
        case .light:
            lightPlated(view, shape: shape)
                .glassBandBottomFade(
                    AppleGlassChromeMetrics.glassBandBottomFadeHeight,
                    enabled: role.fadesBottomEdge
                )
        case .native:
            nativePlated(view, shape: shape)
                .glassBandBottomFade(
                    AppleGlassChromeMetrics.glassBandBottomFadeHeight,
                    enabled: role.fadesBottomEdge
                )
        }
    }

    /// `.light` (default): the refined frosted Liquid Glass.
    /// - A system `Material` underlay raises the effective blur so the
    ///   background turns into colour blocks and shapes are unrecognisable.
    /// - `Glass.tint(_:)` is the thin tint layer that lowers background
    ///   contrast, stopping dark text / borders reading as a reflection.
    @ViewBuilder
    private func lightPlated<V: View, S: Shape>(_ view: V, shape: S) -> some View {
        switch AppleGlassChromeBackend.resolved {
        case .swiftUIGlassEffect:
            #if compiler(>=6.2)
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: CGFloat(0)) {
                    view
                        .background(role.lightUnderlayMaterial, in: shape)
                        .glassEffect(
                            .regular.tint(AppleGlassChromeMetrics.lightTint),
                            in: shape
                        )
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
        case .nsVisualEffectView, .unpainted:
            degraded(view, shape: shape)
        }
    }

    /// `.native`: system vibrancy material, selected by scene, with a
    /// matching blending mode. Kept alongside `.light`, never deleted.
    @ViewBuilder
    private func nativePlated<V: View, S: Shape>(_ view: V, shape: S) -> some View {
        view.background { AppleGlassChromeNativePlate(role: role) }
            .clipShape(shape)
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
    /// Fallback material. Plates over the canvas are raised to the stronger
    /// material Apple ships for floating surfaces (`.hudWindow`, `.popover`),
    /// so text on the plate stays readable while a node passes underneath.
    /// The columns keep `.sidebar`; in-bar controls keep the window background.
    var fallbackMaterial: NSVisualEffectView.Material {
        switch self {
        case .bottomBarCapsule, .canvasFloatingButton:
            .hudWindow
        case .floatingPanel:
            .popover
        case .inspectorPanel, .sidebarColumn:
            .sidebar
        case .segmentedContainer, .iconButton, .toolbarFloatingButton:
            .underWindowBackground
        }
    }

    /// What the plate samples. `behindWindow` reads the desktop behind the
    /// window, which is why a capsule sitting on canvas nodes looked cut off:
    /// it neither diffused nor covered them. Only chrome that floats over the
    /// canvas switches to `.withinWindow`; the columns stay on `.behindWindow`.
    var fallbackBlendingMode: NSVisualEffectView.BlendingMode {
        floatsOverContent ? .withinWindow : .behindWindow
    }

    /// `.native` scene -> Apple system material.
    var nativeMaterial: NSVisualEffectView.Material {
        switch nativeScene {
        case .sidebar: .sidebar
        case .header: .headerView
        case .hud: .hudWindow
        }
    }

    /// `.native` scene -> Apple blending mode.
    var nativeBlendingMode: NSVisualEffectView.BlendingMode {
        switch nativeScene {
        case .sidebar: .behindWindow
        case .header, .hud: .withinWindow
        }
    }

    var plateCornerRadius: CGFloat {
        switch self {
        case .inspectorPanel, .floatingPanel:
            AppleGlassChromeMetrics.panelCornerRadius
        case .sidebarColumn:
            AppleGlassChromeMetrics.sidebarCornerRadius
        case .iconButton:
            22
        case .segmentedContainer, .bottomBarCapsule, .toolbarFloatingButton, .canvasFloatingButton:
            20
        }
    }
}
#endif

#if os(iOS)
extension AppleGlassChromeRole {
    /// `.native` scene -> Apple `UIBlurEffect` system material (the iOS
    /// counterpart of `NSVisualEffectView.Material`).
    var nativeBlurStyle: UIBlurEffect.Style {
        switch nativeScene {
        case .sidebar: .systemMaterial
        case .header: .systemChromeMaterial
        case .hud: .systemThickMaterial
        }
    }
}
#endif

#if os(macOS)
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
        view.blendingMode = role.fallbackBlendingMode
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        view.layer?.backgroundColor = nil
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
#endif

#if os(macOS)
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
        view.blendingMode = role.fallbackBlendingMode
        view.layer?.cornerRadius = role.plateCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = nil
    }
}

/// `.native` implementation on macOS: the system vibrancy view with the
/// scene-specific material and blending mode.
@MainActor
private struct AppleGlassChromeNativePlate: NSViewRepresentable {
    var role: AppleGlassChromeRole

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = role.nativeMaterial
        view.blendingMode = role.nativeBlendingMode
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        view.layer?.backgroundColor = nil
        view.layer?.cornerRadius = role.plateCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
#endif

#if os(iOS)
/// `.native` implementation on iOS: the system `UIVisualEffectView` with the
/// scene-specific `UIBlurEffect` material (Apple's official iOS counterpart
/// of the `NSVisualEffectView` path above).
@MainActor
private struct AppleGlassChromeNativePlate: UIViewRepresentable {
    var role: AppleGlassChromeRole

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: role.nativeBlurStyle))
        view.backgroundColor = .clear
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = UIBlurEffect(style: role.nativeBlurStyle)
    }
}
#endif
