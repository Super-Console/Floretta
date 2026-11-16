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
/// iOS inspector and the editor outline column (both platforms) use the path
/// below. `sidebarColumn` is the token for the editor outline column; the
/// `NavigationSplitView` sidebar it was first written for is gone, so the
/// macOS inspector is the only surface here that really owns a window edge.
///
/// Two official implementations are kept side by side and selected by
/// `GlassChromeConfiguration.renderingStyle` (default `.light`):
/// - `.light` is the shipped "frosted" Liquid Glass: `GlassEffectContainer`
///   + `glassEffect(.regular.tint(_:), in:)`, with a system `Material`
///   underlay that diffuses the background into color blocks. The plate's edge
///   is the shape's own edge: nothing here paints a fade, a wash, or a shadow
///   on top of Apple's glass.
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
/// 3. `NSVisualEffectView` as the older-OS fallback. `sampleSource` is the one
///    rule that decides what a plate blurs — **the layer it actually covers**
///    (采样对象是它身后真正被它遮住的那层东西), never a habit or a shape:
///    - Chrome that covers canvas pixels blurs the window's own content
///      (`blendingMode: .withinWindow`). That is the two bottom capsules and
///      the banners (material `.hudWindow` / `.popover`), and the editor
///      outline column (material `.sidebar`), which is a panel floating over
///      the canvas rather than a column of the window. A node passing under
///      such a plate is diffused instead of showing through with a sharp edge
///      that reads as a cut-off bar, and its text stays readable.
///    - A column that owns the window's edge covers nothing but the window
///      backdrop, so it samples it (`blendingMode: .behindWindow`). The macOS
///      inspector is that column, and it draws no plate here at all because
///      the system `.inspector` column already supplies the glass. Sampling
///      `.behindWindow` for a panel that sits on canvas pixels is the
///      "solid grey plate" bug: it blurs the desktop behind the window while
///      the canvas it covers stays sharp underneath.
///    - Icon buttons and toolbar buttons inherit the bar they sit in and use
///      `.underWindowBackground`. A segmented control is not plated at all:
///      the system control draws its own background, and a capsule around it
///      was a second surface on top of Apple's.
/// 4. On iOS before Liquid Glass, the system control stays as it is. This
///    file does not invent a blur, a frosted fill, or a shadow.
///
/// No role fades an edge. A glass band used to be masked with an alpha
/// gradient so its bottom edge "dissolved" into the canvas; that is a
/// hand-drawn gradient on top of an official material, and it made the two
/// bottom capsules and the segmented control read as a filter rather than as
/// Apple's controls. The user asked for the system controls back, so that mask
/// and its helper are gone: every plate now ends on its own shape.
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
    ///
    /// The sample source is platform-split because the surface is: on macOS
    /// this is the system `.inspector` column that owns the window's trailing
    /// edge (`windowBackdrop`, and no plate is drawn here); on iOS the
    /// inspector is presented over the canvas — a trailing column at regular
    /// width, a sheet at compact width — so it covers canvas pixels and
    /// samples `windowContent`.
    case inspectorPanel
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
    /// The editor outline column, on both platforms.
    ///
    /// It is a 300pt-wide panel inside the canvas `ZStack`, so it floats over
    /// the canvas and covers canvas pixels: it samples `windowContent`. The
    /// `NavigationSplitView` sidebar this token was first written for no
    /// longer exists — the home page is one column — so no call site of this
    /// role owns a window edge.
    case sidebarColumn
    /// Floating banners, status strips, and the in-canvas audio bar.
    case floatingPanel
}

/// What a glass plate samples: **the layer it actually covers**, not the shape
/// it is drawn in and not the role's name.
///
/// 采样对象是它身后真正被它遮住的那层东西。A panel that floats beside or over
/// the canvas covers canvas pixels, so it has to blur those pixels. Only a
/// surface that owns the window's edge covers nothing but the window backdrop,
/// and only that surface may sample behind the window.
///
/// This is the single place the question is answered. `fallbackBlendingMode`
/// and `nativeBlendingMode` both read it, so the `.light` A/B style and the
/// `.native` style cannot drift apart.
enum GlassChromeSampleSource: String, Equatable {
    /// The window's own content: canvas pixels, and the app content under a
    /// sheet. Maps to `NSVisualEffectView.BlendingMode.withinWindow`.
    case windowContent
    /// The backdrop behind the window, which is only visible through an
    /// otherwise empty column. Maps to `.behindWindow`.
    case windowBackdrop
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
        case .iconButton, .bottomBarCapsule, .sidebarColumn, .floatingPanel, .canvasFloatingButton:
            return true
        }
    }

    /// What this plate samples. The rule lives here once, so every style — the
    /// SwiftUI `.light` underlay, the AppKit fallback, and the `.native`
    /// vibrancy view — blurs the same layer for the same role.
    ///
    /// - Canvas pixels (`windowContent`): the bottom capsules, the banners, the
    ///   audio bar, the Zen exit, and the editor outline column — a panel that
    ///   floats beside the canvas covers canvas pixels like any other floater.
    /// - Window backdrop (`windowBackdrop`): only the macOS inspector, whose
    ///   column is the window's trailing edge and whose glass the system
    ///   draws. On iOS that same inspector covers canvas pixels instead.
    /// - In-bar controls inherit their bar, which owns the window edge.
    var sampleSource: GlassChromeSampleSource {
        switch self {
        case .bottomBarCapsule, .floatingPanel, .canvasFloatingButton, .sidebarColumn:
            return .windowContent
        case .inspectorPanel:
            #if os(macOS)
            return .windowBackdrop
            #else
            return .windowContent
            #endif
        case .iconButton, .toolbarFloatingButton:
            return .windowBackdrop
        }
    }

    /// Underlay material for the `.light` path. It follows what the plate
    /// covers: a small plate with one label takes the thick material, a tall
    /// text column takes `.regularMaterial` — SwiftUI's counterpart of the
    /// `.sidebar` vibrancy the native path uses, so rows stay legible over a
    /// busy canvas without turning the plate into a solid slab — and the
    /// in-bar controls keep the thin one they sit on.
    var lightUnderlayMaterial: Material {
        switch self {
        case .bottomBarCapsule, .floatingPanel, .canvasFloatingButton:
            return .thickMaterial
        case .sidebarColumn, .inspectorPanel:
            return .regularMaterial
        case .iconButton, .toolbarFloatingButton:
            return .thinMaterial
        }
    }

    /// Scene used to pick the `.native` system material on both platforms.
    var nativeScene: GlassNativeScene {
        switch self {
        case .sidebarColumn, .inspectorPanel:
            return .sidebar
        case .iconButton, .toolbarFloatingButton:
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

    /// Lets the panel's glass show through the form instead of a form-painted
    /// background. Does not restyle the form's pickers, sliders, or toggles.
    ///
    /// Both platforms: the Mac panel is the system inspector column's own Liquid
    /// Glass, so the grouped form has to stop painting its scroll background for
    /// that glass to be visible at all. On macOS the same layer is where the
    /// grouped section plates are drawn, which is why the inspector's rows carry
    /// `inspectorRowBlock(enabled:)` plates of their own; iOS keeps its
    /// inset-grouped cards and adds nothing.
    @ViewBuilder
    func appleGlassInspectorFormPlate() -> some View {
        self.scrollContentBackground(.hidden)
    }

    /// Keep the native sidebar selection inset while leaving selection drawing
    /// to `List(.sidebar)`; a custom row background would layer a second shape.
    ///
    /// iOS gets its own numbers: the phone's outline is a full-width panel whose
    /// header is padded 12pt, so rows line up with that header instead of
    /// hugging the glass edge, and a 4pt vertical inset keeps every row at or
    /// above the 44pt touch target.
    func sidebarSelectionInset() -> some View {
        #if os(iOS)
        return self
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
        #else
        let inset = AppleGlassChromeMetrics.sidebarRowInset
        return self
            .listRowInsets(EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset))
            .listRowBackground(Color.clear)
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
        case .bottomBarCapsule, .toolbarFloatingButton, .canvasFloatingButton:
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
        case .toolbarFloatingButton, .bottomBarCapsule, .canvasFloatingButton:
            view.foregroundStyle(.primary)
        }
    }

    /// One plate, whatever the style: the shape's own edge. The soft
    /// bottom-edge fade that used to be masked over the bottom capsules and
    /// banners was a hand-painted gradient on top of Apple's glass — the fade
    /// the user reported on both platforms — so the plate now ends where its
    /// shape ends and the system glass is the only surface.
    @ViewBuilder
    private func plated<V: View, S: Shape>(_ view: V, shape: S) -> some View {
        switch GlassChromeConfiguration.renderingStyle {
        case .light:
            lightPlated(view, shape: shape)
        case .native:
            nativePlated(view, shape: shape)
        }
    }

    /// `.light` (default): the refined frosted Liquid Glass.
    /// - `glassEffect` samples the window's own content by construction, so a
    ///   plate over the canvas refracts the canvas. It is the reason a panel
    ///   here needs no blending mode; the material underlay is what decides how
    ///   much of that content survives.
    /// - A system `Material` underlay raises the effective blur so the
    ///   background turns into colour blocks and shapes are unrecognisable.
    ///   `lightUnderlayMaterial` follows the same sample-source rule as the
    ///   AppKit plates: a text column over the canvas takes `.regularMaterial`,
    ///   a one-line capsule takes `.thickMaterial`.
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

    /// `.native`: system vibrancy material, selected by scene, with the
    /// sample-source blending mode. Kept alongside `.light`, never deleted.
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
    /// The outline panel keeps `.sidebar` — the material Apple documents for a
    /// text column — and it is paired with `.withinWindow` here, so that
    /// material now diffuses the canvas the panel covers instead of the
    /// desktop behind the window. In-bar controls keep the window background.
    var fallbackMaterial: NSVisualEffectView.Material {
        switch self {
        case .bottomBarCapsule, .canvasFloatingButton:
            .hudWindow
        case .floatingPanel:
            .popover
        case .inspectorPanel, .sidebarColumn:
            .sidebar
        case .iconButton, .toolbarFloatingButton:
            .underWindowBackground
        }
    }

    /// What the plate samples, spelled once. `.behindWindow` reads the desktop
    /// behind the window: correct only for a surface that owns the window edge
    /// and covers nothing else, wrong for anything that sits on canvas pixels
    /// (it blurs the desktop while the canvas underneath stays sharp, which is
    /// the solid grey panel). `.withinWindow` reads the window's own content,
    /// which is exactly what a panel floating over the canvas covers.
    var blendingMode: NSVisualEffectView.BlendingMode {
        sampleSource == .windowContent ? .withinWindow : .behindWindow
    }

    /// Fallback plate. Same mode as the role: one answer, two callers.
    var fallbackBlendingMode: NSVisualEffectView.BlendingMode { blendingMode }

    /// `.native` scene -> Apple system material.
    var nativeMaterial: NSVisualEffectView.Material {
        switch nativeScene {
        case .sidebar: .sidebar
        case .header: .headerView
        case .hud: .hudWindow
        }
    }

    /// `.native` plate blending mode. The scene picks the material; the sample
    /// source picks what is blurred, so the `.native` A/B style cannot sample a
    /// different layer than the `.light` one.
    var nativeBlendingMode: NSVisualEffectView.BlendingMode { blendingMode }

    var plateCornerRadius: CGFloat {
        switch self {
        case .inspectorPanel, .floatingPanel:
            AppleGlassChromeMetrics.panelCornerRadius
        case .sidebarColumn:
            AppleGlassChromeMetrics.sidebarCornerRadius
        case .iconButton:
            22
        case .bottomBarCapsule, .toolbarFloatingButton, .canvasFloatingButton:
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

/// Apple's own motion, for chrome feedback, in one place — and the one place
/// that honours Reduce Motion.
///
/// Nothing here invents a curve: `.snappy` and `.smooth` are the system
/// animations, every duration stays well under 0.35 s, and nothing is drawn to
/// fake a transition. A control that changes state gets the system's press
/// feedback from its own button style; this enum only decides the curve for the
/// surfaces this file's chrome hosts (a panel appearing, an inspector page
/// switching, a symbol replacing another).
///
/// Reduce Motion: `resolved` returns `nil`, and both `withAnimation(nil)` and
/// `.animation(nil, value:)` apply the change with no animation at all. Passing
/// the environment value through this function is the whole rule, so no call
/// site branches on the setting itself.
enum ChromeMotion {
    /// A panel appearing or a page switching: short and springless enough that
    /// a 300 pt column does not appear to slide on its own.
    static let panel: Animation = .snappy(duration: 0.24)
    /// A control changing state where no surface moves.
    static let control: Animation = .smooth(duration: 0.18)

    /// The animation to use, or `nil` when the reader asked for Reduce Motion.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
