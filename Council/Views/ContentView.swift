//
//  ContentView.swift
//  Council
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Charts
import UserNotifications

extension Color {
    /// A color that resolves to `light` or `dark` based on the active appearance,
    /// which is driven app-wide by `.preferredColorScheme` (see ContentView).
    static func adaptive(_ light: Color, _ dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

extension NSView {
    /// Depth-first search for a descendant view carrying this identifier.
    func descendant(withIdentifier id: String) -> NSView? {
        if identifier?.rawValue == id { return self }
        for sub in subviews {
            if let found = sub.descendant(withIdentifier: id) { return found }
        }
        return nil
    }
}

/// Behind-window blur: shows the desktop / other windows behind this app, frosted. `behindWindow`
/// blending is what makes the whole app read as one sheet of glass. It also makes its host window
/// transparent so the blur actually reaches the desktop instead of an opaque backing.
struct VisualEffectBackground: NSViewRepresentable {
    /// true = behind-window (the desktop shows through, gorgeous but the transparent window forces
    /// the window server to recomposite against the desktop on every scroll frame → jank).
    /// false = within-window on an opaque window (still frosted glass, just doesn't reveal the
    /// actual desktop) → the window server never touches the desktop → buttery scrolling.
    var desktopGlass: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = desktopGlass ? .behindWindow : .withinWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.blendingMode = desktopGlass ? .behindWindow : .withinWindow
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = !desktopGlass
            w.backgroundColor = desktopGlass ? .clear : .windowBackgroundColor
        }
    }
}

/// "Liquid glass" palette — a deep slate, frosted surfaces, and a blue accent, with a soft
/// light variant. Token names are kept from the old brutalist theme so call sites don't churn;
/// only the values changed. `ink` = primary text/icons, `sub`/`dim` = secondary, `paper` = the
/// (now mostly translucent) surface tint, `bg` = the gradient base.
enum Blue {
    // Neutral grayscale glass — no hue. Dark base ≈ #121212 / #0e0e0e, light ≈ soft warm-white.
    static let bg    = Color.adaptive(Color(red: 0.95,  green: 0.95,  blue: 0.96),  Color(red: 0.075, green: 0.075, blue: 0.078)) // base
    static let paper = Color.adaptive(.white,                                       Color(red: 0.12,  green: 0.12,  blue: 0.125)) // solid fallback
    static let ink   = Color.adaptive(Color(red: 0.10, green: 0.10, blue: 0.11),    Color(red: 0.95,  green: 0.95,  blue: 0.96))  // primary text
    static let grid  = Color.adaptive(Color(red: 0.90,  green: 0.90,  blue: 0.91),  Color(red: 0.18,  green: 0.18,  blue: 0.19))  // (legacy; unused)
    static let sub   = Color.adaptive(Color(red: 0.42,  green: 0.42,  blue: 0.44),  Color(red: 0.74,  green: 0.75,  blue: 0.77))  // secondary text (on-surface-variant)
    static let dim   = Color.adaptive(Color(red: 0.64,  green: 0.64,  blue: 0.66),  Color(red: 0.46,  green: 0.46,  blue: 0.48))  // placeholder / disabled
    static let red   = Color.adaptive(Color(red: 0.82,  green: 0.24,  blue: 0.28),  Color(red: 1.0,   green: 0.55,  blue: 0.52))  // error (kept — functional)

    // Glass tokens. `accent` is now monochrome (near-ink) — used sparingly for a primary tint;
    // most "active" emphasis comes from a brighter glass fill + border + white glow, not color.
    static let accent      = Color.adaptive(Color(red: 0.20, green: 0.50, blue: 0.95), Color(red: 0.40, green: 0.66, blue: 1.0))  // the single accent
    static let glassFill   = Color.adaptive(Color.white.opacity(0.28),                Color.white.opacity(0.045)) // thin tint — let the material + backdrop show through
    static let glassStroke = Color.adaptive(Color.black.opacity(0.08),                Color.white.opacity(0.16))  // hairline edge
    static let glassBright = Color.adaptive(Color.black.opacity(0.10),                Color.white.opacity(0.12))  // active/selected/hover fill — DARK in light mode so it actually shows on light backgrounds
    static let ok          = Color.adaptive(Color(red: 0.30, green: 0.32, blue: 0.34), Color(red: 0.88, green: 0.90, blue: 0.93)) // "done" → bright neutral
    static let warn        = Color.adaptive(Color(red: 0.55, green: 0.56, blue: 0.58), Color(red: 0.60, green: 0.62, blue: 0.66)) // "standby" → mid neutral

    /// Background tints for the palette (index 0 = none → pure glass). One color = a solid wash;
    /// two colors = a gradient mix. Kept subtle over the behind-window vibrancy.
    struct Tint { let name: String; let colors: [Color] }
    static let bgTints: [Tint] = [
        Tint(name: "None",     colors: []),
        // Solid hues:
        Tint(name: "Blue",     colors: [Color(red: 0.20, green: 0.45, blue: 0.97)]),
        Tint(name: "Cyan",     colors: [Color(red: 0.10, green: 0.68, blue: 0.90)]),
        Tint(name: "Teal",     colors: [Color(red: 0.08, green: 0.60, blue: 0.58)]),
        Tint(name: "Green",    colors: [Color(red: 0.20, green: 0.66, blue: 0.32)]),
        Tint(name: "Lime",     colors: [Color(red: 0.58, green: 0.76, blue: 0.18)]),
        Tint(name: "Amber",    colors: [Color(red: 0.97, green: 0.64, blue: 0.12)]),
        Tint(name: "Orange",   colors: [Color(red: 0.96, green: 0.46, blue: 0.14)]),
        Tint(name: "Rose",     colors: [Color(red: 0.93, green: 0.24, blue: 0.40)]),
        Tint(name: "Pink",     colors: [Color(red: 0.95, green: 0.42, blue: 0.74)]),
        Tint(name: "Violet",   colors: [Color(red: 0.54, green: 0.30, blue: 0.94)]),
        Tint(name: "Indigo",   colors: [Color(red: 0.34, green: 0.32, blue: 0.88)]),
        Tint(name: "Sky",      colors: [Color(red: 0.35, green: 0.65, blue: 0.98)]),
        Tint(name: "Emerald",  colors: [Color(red: 0.10, green: 0.72, blue: 0.50)]),
        Tint(name: "Gold",     colors: [Color(red: 0.92, green: 0.74, blue: 0.18)]),
        Tint(name: "Coral",    colors: [Color(red: 0.98, green: 0.45, blue: 0.40)]),
        Tint(name: "Crimson",  colors: [Color(red: 0.82, green: 0.10, blue: 0.24)]),
        Tint(name: "Magenta",  colors: [Color(red: 0.85, green: 0.18, blue: 0.62)]),
        Tint(name: "Lavender", colors: [Color(red: 0.66, green: 0.56, blue: 0.92)]),
        Tint(name: "Slate",    colors: [Color(red: 0.34, green: 0.40, blue: 0.50)]),
        Tint(name: "Graphite", colors: [Color(red: 0.40, green: 0.42, blue: 0.46)]),
        // Two-color mixes (gradients) — drawn split in the swatch, blended on the backdrop:
        Tint(name: "Sunset",   colors: [Color(red: 0.98, green: 0.55, blue: 0.15), Color(red: 0.90, green: 0.20, blue: 0.45)]),
        Tint(name: "Ocean",    colors: [Color(red: 0.14, green: 0.45, blue: 0.98), Color(red: 0.06, green: 0.64, blue: 0.62)]),
        Tint(name: "Aurora",   colors: [Color(red: 0.10, green: 0.64, blue: 0.55), Color(red: 0.52, green: 0.30, blue: 0.94)]),
        Tint(name: "Berry",    colors: [Color(red: 0.54, green: 0.24, blue: 0.88), Color(red: 0.95, green: 0.34, blue: 0.70)]),
        Tint(name: "Ember",    colors: [Color(red: 0.88, green: 0.18, blue: 0.24), Color(red: 0.97, green: 0.62, blue: 0.16)]),
        Tint(name: "Mint",     colors: [Color(red: 0.26, green: 0.82, blue: 0.50), Color(red: 0.10, green: 0.66, blue: 0.78)]),
        Tint(name: "Peach",    colors: [Color(red: 0.98, green: 0.70, blue: 0.30), Color(red: 0.95, green: 0.42, blue: 0.66)]),
        Tint(name: "Lagoon",   colors: [Color(red: 0.12, green: 0.70, blue: 0.86), Color(red: 0.18, green: 0.68, blue: 0.42)]),
        Tint(name: "Galaxy",   colors: [Color(red: 0.28, green: 0.24, blue: 0.78), Color(red: 0.80, green: 0.26, blue: 0.70)]),
        Tint(name: "Magma",    colors: [Color(red: 0.86, green: 0.16, blue: 0.20), Color(red: 0.97, green: 0.52, blue: 0.14)]),
        Tint(name: "Dusk",     colors: [Color(red: 0.30, green: 0.28, blue: 0.72), Color(red: 0.85, green: 0.30, blue: 0.45)]),
        Tint(name: "Tropical", colors: [Color(red: 0.55, green: 0.78, blue: 0.20), Color(red: 0.10, green: 0.70, blue: 0.80)]),
        Tint(name: "Candy",    colors: [Color(red: 0.96, green: 0.45, blue: 0.78), Color(red: 0.55, green: 0.32, blue: 0.92)]),
        Tint(name: "Steel",    colors: [Color(red: 0.36, green: 0.42, blue: 0.52), Color(red: 0.14, green: 0.62, blue: 0.78)]),
        Tint(name: "Sunrise",  colors: [Color(red: 0.98, green: 0.78, blue: 0.25), Color(red: 0.96, green: 0.42, blue: 0.16)]),
        Tint(name: "Nebula",   colors: [Color(red: 0.52, green: 0.28, blue: 0.92), Color(red: 0.14, green: 0.66, blue: 0.86)]),
        Tint(name: "Forest",   colors: [Color(red: 0.18, green: 0.55, blue: 0.30), Color(red: 0.10, green: 0.62, blue: 0.60)]),
    ]
    /// Fill style for a tint index (nil = none). Shared by the swatch and the backdrop wash.
    static func tintStyle(_ i: Int) -> AnyShapeStyle? {
        guard i > 0, i < bgTints.count, !bgTints[i].colors.isEmpty else { return nil }
        let c = bgTints[i].colors
        return c.count == 1
            ? AnyShapeStyle(c[0])
            : AnyShapeStyle(LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    static func serif(_ s: CGFloat, _ w: Font.Weight = .bold) -> Font { .system(size: s, weight: w, design: .serif) }
    static func mono(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .monospaced) }
    static func body(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w) }
}

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT KNOBS — live-tunable in the app. Press ⌘D to open the sliders, drag to
// taste, then screenshot the values and tell me — I'll bake them in as defaults.
// ─────────────────────────────────────────────────────────────────────────────
@MainActor @Observable
final class Layout {
    static let shared = Layout()

    var windowTopInset: CGFloat   = 4    // gap above the cards (clears the traffic lights)
    var windowSideInset: CGFloat  = 12   // left/right margin around everything
    var windowBottomInset: CGFloat = 11  // bottom margin
    var sidebarGap: CGFloat       = 9    // space between sidebar and the canvas
    var sidebarWidth: CGFloat     = 222  // sidebar card width
    var sidebarTopInset: CGFloat  = 5    // space above NEW DIRECTIVE inside the sidebar
    var panelGap: CGFloat         = 32   // space between the 3 advisor panels
    var canvasRowGap: CGFloat     = 9    // space between round-bar / panels / input
    var panelCorner: CGFloat      = 30   // advisor panel corner radius
    var roundBarTop: CGFloat      = -6   // shift the ROUND row up (−) / down (+); panels unaffected
    var exportY: CGFloat          = -4   // shift JUST the EXPORT button up (−) / down (+)

    /// (label, keyPath, range) for the tuner UI.
    var knobs: [(String, ReferenceWritableKeyPath<Layout, CGFloat>, ClosedRange<CGFloat>)] {
        [("Window Top", \.windowTopInset, 0...80),
         ("Window Sides", \.windowSideInset, 0...60),
         ("Window Bottom", \.windowBottomInset, 0...60),
         ("Sidebar Gap", \.sidebarGap, 0...60),
         ("Sidebar Width", \.sidebarWidth, 150...360),
         ("Sidebar Top", \.sidebarTopInset, 0...80),
         ("Panel Gap", \.panelGap, 0...60),
         ("Row Gap", \.canvasRowGap, -30...50),
         ("Panel Corner", \.panelCorner, 0...40),
         ("Round Bar Y", \.roundBarTop, -40...40),
         ("Export Y", \.exportY, -40...40)]
    }
}

/// The live layout tuner overlay (⌘D). Drag sliders, watch the layout update instantly.
struct LayoutTuner: View {
    @Bindable var layout = Layout.shared
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LAYOUT TUNER").font(Blue.mono(11, .bold)).tracking(2).foregroundStyle(Blue.ink)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Blue.sub)
            }
            ForEach(Array(layout.knobs.enumerated()), id: \.offset) { _, knob in
                let (label, kp, range) = knob
                HStack(spacing: 10) {
                    Text(label).font(Blue.mono(9)).foregroundStyle(Blue.sub)
                        .frame(width: 92, alignment: .leading)
                    Slider(value: Binding(get: { layout[keyPath: kp] },
                                          set: { layout[keyPath: kp] = $0.rounded() }), in: range)
                    Text("\(Int(layout[keyPath: kp]))").font(Blue.mono(10, .bold)).foregroundStyle(Blue.ink)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(20)
    }
}

/// Frosted-glass surface. On macOS 26+ this uses Apple's real Liquid Glass (`.glassEffect`),
/// which genuinely refracts + reflects whatever is behind it. On older systems it falls back to
/// a hand-built material + hairline approximation so the app still builds and looks reasonable.
struct GlassPanel: ViewModifier {
    var corner: CGFloat = 18
    var strokeOpacity: Double = 1
    /// Performance mode forces the cheap material instead of real Liquid Glass (off by default —
    /// the beautiful path). A user-facing escape hatch for weaker machines.
    @AppStorage("council.liteMode") private var liteMode = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !liteMode {
            // Real Liquid Glass. `.rect(cornerRadius:)` is the shape API glassEffect expects.
            content.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            content
                .background(.regularMaterial, in: shape)
                .background(Blue.glassFill, in: shape)
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .overlay(shape.strokeBorder(Blue.glassStroke.opacity(strokeOpacity), lineWidth: 1))
                .clipShape(shape)
                .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 14)
        }
    }
}
/// A small control surface (button / chip / field) in real Liquid Glass, capsule or rounded-rect.
/// Falls back to a material on pre-26 systems. `tinted`/`interactive` map to the Glass options.
struct GlassControl: ViewModifier {
    var corner: CGFloat? = nil          // nil → capsule
    var tinted: Bool = false
    var interactive: Bool = false
    @AppStorage("council.liteMode") private var liteMode = false
    @available(macOS 26.0, *)
    private var glass: Glass {
        var g: Glass = .regular
        if tinted { g = g.tint(Blue.accent) }
        if interactive { g = g.interactive() }
        return g
    }
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !liteMode {
            if let corner { content.glassEffect(glass, in: .rect(cornerRadius: corner)) }
            else { content.glassEffect(glass, in: .capsule) }
        } else {
            let bg = AnyShapeStyle(.ultraThinMaterial)
            if let corner {
                content.background(bg, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
            } else {
                content.background(bg, in: Capsule()).overlay(Capsule().strokeBorder(Blue.glassStroke, lineWidth: 1))
            }
        }
    }
}

extension View {
    func glassPanel(corner: CGFloat = 18, strokeOpacity: Double = 1) -> some View {
        modifier(GlassPanel(corner: corner, strokeOpacity: strokeOpacity))
    }
    /// Capsule glass control (default) or rounded-rect when `corner` is given.
    func glassControl(corner: CGFloat? = nil, tinted: Bool = false, interactive: Bool = false) -> some View {
        modifier(GlassControl(corner: corner, tinted: tinted, interactive: interactive))
    }
}

/// Hover affordance: on pointer-over, a clean frosted-glass pill fades in behind the content with
/// a faint light edge — the calm "liquid glass" touch response (no flowing light).
struct GlassHover: ViewModifier {
    var corner: CGFloat = 10
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // Adaptive tint: a slight DARK wash in light mode (so the hover box actually
                    // shows over light backgrounds), a slight light wash in dark mode.
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.adaptive(.black.opacity(0.10), .white.opacity(0.14))))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .opacity(hovered ? 1 : 0)
            }
            .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hovered = h } }
    }
}
extension View {
    func glassHover(corner: CGFloat = 10) -> some View { modifier(GlassHover(corner: corner)) }
}

/// A soft glow (ink → white in dark mode) that follows the cursor inside a view's bounds
/// on hover, clipped to the box. When `selected` and not hovering, it rests near the top as
/// a steady indicator. Used on buttons and the Light/Dark options.
private struct CursorGlow: ViewModifier {
    var selected: Bool = false
    @State private var loc: CGPoint?
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geo in
                if selected || loc != nil {
                    // Selected → fixed, centered glow (ignores the cursor). Otherwise it follows the cursor.
                    Circle()
                        .fill(Blue.ink.opacity(0.22))
                        .frame(width: 120, height: 120)
                        .blur(radius: 30)
                        .position(selected
                                  ? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                  : (loc ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)))
                }
            }
            // Feathered mask instead of a hard clip — the glow fades out toward the edges,
            // so no rectangular boundary line appears.
            .mask(Rectangle().fill(.black).blur(radius: 12))
            .allowsHitTesting(false)
        }
        .onContinuousHover { phase in
            if case .active(let p) = phase { loc = p } else { loc = nil }
        }
        .animation(.easeOut(duration: 0.14), value: loc)
    }
}
private extension View {
    func cursorGlow(selected: Bool = false) -> some View { modifier(CursorGlow(selected: selected)) }
}

struct ContentView: View {
    let store: CouncilStore
    @State private var query: String = ""
    @State private var isAsking = false
    /// The in-flight round Task, so it can be cancelled (Stop).
    @State private var runningTask: Task<Void, Never>?

    /// Optional image attached to the next directive (sent to every connected seat).
    @State private var pickedImage: NSImage?
    @State private var isDropTargeted = false
    @State private var showImagePreview = false

    /// Appearance: "light" (default) or "dark". Toggled from Settings, not the main screen.
    @AppStorage("council.appearance") private var appearance = "light"
    /// Whether exported share images carry the "made with Council" watermark (default on).
    @AppStorage("council.shareWatermark") private var shareWatermark = true
    @State private var showSettings = false

    /// Left panel can be collapsed to give the canvas the full width.
    @State private var sidebarOpen = true

    /// Local key monitor: pressing Return while nothing is focused jumps into the composer.
    @State private var keyMonitor: Any?

    /// A provider pick awaiting confirmation because it duplicates another seat (token warning).
    struct PendingPick: Identifiable { let id = UUID(); let provider: LLMProvider; let seatID: Int }
    @State private var pendingPick: PendingPick?

    /// Which advisor panel the cursor is over — flattens its perspective tilt for easy reading.
    @State private var hoveredSeat: Int?
    @State private var handleHover = false

    /// Live layout tuner (⌘D) — drag sliders to dial in spacing, then tell me the numbers.
    @Bindable private var layout = Layout.shared
    @State private var showTuner = false

    /// Which canvas the user is looking at: the 3-panel round, or a full-width deliberation artifact.
    enum CanvasMode { case panels, divergence, synthesis }
    @State private var canvasMode: CanvasMode = .panels

    /// Top-level screen: the Home dashboard (landing) or the live roundtable.
    enum Screen { case home, council }
    @State private var screen: Screen = .home

    /// History list state.
    @State private var historyQuery = ""
    @State private var renamingSession: UUID?
    @State private var renameText = ""

    /// First-run onboarding — shown once, then never again.
    @AppStorage("council.didOnboard") private var didOnboard = false

    /// Background tint index into Blue.bgTints (0 = none/pure glass). User-chosen via the palette.
    @AppStorage("council.bgTint") private var bgTintIndex = 0
    /// Performance mode: material instead of Liquid Glass + opaque (no desktop-through) window.
    /// Off by default — the full beautiful glass. A toggle for users on weaker machines.
    @AppStorage("council.liteMode") private var liteMode = false

    /// Ask-from-home composer text (separate from the roundtable composer's `query`).
    @State private var homeQuery = ""

    private var scheme: ColorScheme { appearance == "dark" ? .dark : .light }

    init(store: CouncilStore) { self.store = store }

    var body: some View {
        mainUI
        // Fill the whole window so content can't size to its *ideal* width and get re-centered
        // (which is what shifted the view when NEW DIRECTIVE emptied the panels).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(scheme)
        .overlay(alignment: .topTrailing) {
            // Dev-only live layout tuner — must be completely absent from release builds.
            #if DEBUG
            if showTuner { LayoutTuner { showTuner = false }.preferredColorScheme(scheme) }
            #endif
        }
        .background { shortcutButtons }
        .background {
            // ⌘D opens the tuner — DEBUG only, so there is no affordance at all in release.
            #if DEBUG
            Button("") { showTuner.toggle() }.keyboardShortcut("d", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
            #endif
        }
        .overlay {
            if !didOnboard {
                OnboardingCard { withAnimation(.easeInOut(duration: 0.6)) { didOnboard = true } }
                    .preferredColorScheme(scheme)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(store: store, appearance: $appearance) { showSettings = false }
                .preferredColorScheme(scheme)
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    /// Drop keyboard focus from any text field (clicking empty space deselects inputs).
    private func resignFocus() { NSApp.keyWindow?.makeFirstResponder(nil) }

    /// While no field is focused, a plain Return jumps the cursor into the composer so the
    /// user can start typing. While a field IS focused, Return does its normal job (send / newline).
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 36,   // Return
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  let window = NSApp.keyWindow else { return event }
            if window.firstResponder is NSText { return event }   // already typing somewhere
            if let composer = window.contentView?.descendant(withIdentifier: "council.composer") {
                window.makeFirstResponder(composer)
                return nil   // consume — this Return only moved focus
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Invisible buttons that carry keyboard shortcuts (keyboard-first ethos).
    private var shortcutButtons: some View {
        Group {
            Button("") { if !isBusy { store.newSession(); canvasMode = .panels; screen = .council } }
                .keyboardShortcut("n", modifiers: .command)
            Button("") { showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
            Button("") { if store.canGoPrevRound { store.prevRound() } }
                .keyboardShortcut("[", modifiers: .command)
            Button("") { if store.canGoNextRound { store.nextRound() } }
                .keyboardShortcut("]", modifiers: .command)
            Button("") { if store.hasSession { Exporter.copy(store.exportMarkdown()) } }
                .keyboardShortcut("e", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    private var mainUI: some View {
        HStack(spacing: layout.sidebarGap) {
            if sidebarOpen {
                sidebar
                    .overlay(alignment: .trailing) { sidebarHandle }   // stuck to the sidebar's edge
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Group {
                if screen == .home { homeDashboard } else { mainCanvas }
            }
            .overlay(alignment: .leading) { if !sidebarOpen { sidebarHandle } }
        }
        // The glass cards stay BELOW the title-bar strip (top inset clears the traffic lights);
        // only the background extends up under them, so no card overlaps the window controls.
        .padding(.horizontal, layout.windowSideInset)
        .padding(.top, layout.windowTopInset).padding(.bottom, layout.windowBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gridBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { resignFocus() }   // click empty space → deselect any input
    }

    /// Collapse/expand control, integrated onto the leftmost vertical line (replaces the old top bar).
    /// `chevron.left` rotates 180° rather than swapping symbols, so nothing flickers under the cursor.
    private var sidebarHandle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { sidebarOpen.toggle() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Blue.ink)
                .rotationEffect(.degrees(sidebarOpen ? 0 : 180))
                .frame(width: 24, height: 48)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background(Blue.glassBright, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Hover highlight — same feel as every other button.
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.adaptive(.black.opacity(0.10), .white.opacity(0.14)))
                    .opacity(handleHover ? 1 : 0))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(handleHover ? 1.08 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Toggle sidebar")
        .accessibilityLabel(sidebarOpen ? "Collapse sidebar" : "Expand sidebar")
        .offset(x: sidebarOpen ? 12 : 0)   // pokes out past the sidebar's right edge
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { handleHover = h } }
    }


    // MARK: Background grid

    /// Real behind-window vibrancy: the macOS desktop / windows BEHIND this app are blurred and
    /// shown through, so the whole window reads as one piece of frosted glass. The frosted panels
    /// then sit on top of that live, refracted backdrop — the actual "glass" you wanted.
    private var gridBackground: some View {
        let style = Blue.tintStyle(bgTintIndex)
        // Opaque window (no desktop showing through) — the frosted backdrop + Liquid Glass cards stay.
        return VisualEffectBackground(desktopGlass: false)
            // Plain normal-blend film (NO .color blendMode — that forced a full-window offscreen
            // composite every frame and caused the scroll jank). A higher opacity keeps the hue
            // mostly true while staying cheap.
            .overlay { if let style { Rectangle().fill(style).opacity(0.5) } }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.3), value: bgTintIndex)
    }



    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: layout.sidebarTopInset)

            Button(action: { store.newSession(); canvasMode = .panels; screen = .council }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("NEW DIRECTIVE").font(Blue.mono(11, .bold)).tracking(1)
                }
                .foregroundStyle(Blue.ink)
                .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
                .glassHover(corner: 10)            // plain text; the glass panel only appears on hover
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy ? 0.4 : 1)
            .help(isBusy ? "Finish or stop the current generation first" : "Start a new directive")

            modeItem("square.grid.2x2", "HOME",
                     state: screen == .home ? .active : .button,
                     action: { screen = .home })

            modeItem("point.3.connected.trianglepath.dotted", "ROUNDTABLE",
                     state: (screen == .council && canvasMode == .panels) ? .active : .button,
                     action: { screen = .council; canvasMode = .panels })

            modeItem("arrow.2.squarepath", "PEER REVIEW",
                     state: (store.canPeerReview || store.hasPeerReviewForViewedRound) ? .button : .locked,
                     hint: store.hasPeerReviewForViewedRound
                        ? "Show this round's peer review (already generated)"
                        : (store.canPeerReview ? "Models review each other's answers, anonymized"
                                               : "Ask a question first — unlocks once ≥2 models have answered"),
                     action: (store.canPeerReview || store.hasPeerReviewForViewedRound) ? {
                        screen = .council; canvasMode = .panels
                        if !store.hasPeerReviewForViewedRound { runRound { await store.peerReview() } }
                     } : nil)

            modeItem("arrow.triangle.branch", "DIVERGENCE",
                     state: (screen == .council && canvasMode == .divergence) ? .active : (divergenceAvailable ? .button : .locked),
                     hint: divergenceAvailable ? "Map where advisors agree and diverge"
                                               : "Answer ≥2 advisors first",
                     action: divergenceAvailable ? { screen = .council; canvasMode = .divergence } : nil)

            modeItem("rectangle.3.group", "SYNTHESIS",
                     state: (screen == .council && canvasMode == .synthesis) ? .active : (synthesisAvailable ? .button : .locked),
                     hint: synthesisAvailable ? "Final answer that preserves the dissent"
                                              : "Answer ≥2 advisors first",
                     action: synthesisAvailable ? { screen = .council; canvasMode = .synthesis } : nil)

            historySection

            modeItem("gearshape", "SETTINGS", state: .button) { showSettings = true }
                .padding(.bottom, 6)
        }
        .frame(width: layout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .glassPanel(corner: 24)   // floating frosted card, gaps on all sides
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 6)
    }

    /// Sidebar deliberation row. `.button` is a normal tappable row (e.g. SETTINGS).
    private func modeItem(_ icon: String, _ label: String, state: ModeRow.ModeState,
                          hint: String? = nil, action: (() -> Void)? = nil) -> some View {
        ModeRow(icon: icon, label: label, state: state, hint: hint, action: action)
    }

    // MARK: Main canvas

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("HISTORY")
            if store.sessions.count > 3 || !historyQuery.isEmpty {
                PlainTextField(text: $historyQuery, placeholder: "search…", fontSize: 11)
                    .frame(height: 16)
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }
            let results = store.searchedSessions(historyQuery)   // compute once per render
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { session in
                        historyRow(session)
                    }
                    if results.isEmpty {
                        Text(historyQuery.isEmpty ? "No saved directives yet." : "No matches.")
                            .font(Blue.mono(10)).foregroundStyle(Blue.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private func historyRow(_ s: Session) -> some View {
        if renamingSession == s.id {
            PlainTextField(text: $renameText, placeholder: "title", fontSize: 11, onSubmit: {
                store.renameSession(s.id, to: renameText); renamingSession = nil
            })
            .frame(height: 16).padding(.horizontal, 18).padding(.vertical, 10)
        } else {
            Button {
                store.openSession(s); canvasMode = .panels; screen = .council
            } label: {
                Text(s.title.isEmpty ? "Untitled" : s.title)
                    .font(Blue.mono(11)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(s.id == store.currentSession ? Blue.ink : Blue.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(s.id == store.currentSession ? Blue.ink.opacity(0.06) : Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy && s.id != store.currentSession ? 0.4 : 1)
            .contextMenu {
                Button("Rename") { renameText = s.title; renamingSession = s.id }
                Button("Delete", role: .destructive) { store.deleteSession(s.id) }
                    .disabled(isBusy)
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("Copy markdown") { Exporter.copy(store.exportMarkdown()) }
            Button("Save markdown…") { Exporter.saveMarkdown(store.exportMarkdown(), name: "council") }
            Button("Save PDF…") { Exporter.savePDF(store.exportMarkdown(), name: "council") }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .bold))
                Text("EXPORT").font(Blue.mono(9, .bold)).tracking(1)
            }
            .foregroundStyle(store.hasSession ? Blue.ink : Blue.dim)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Blue.glassStroke.opacity(store.hasSession ? 1 : 0.4), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!store.hasSession)
        .accessibilityLabel("Export conversation")
    }

    // MARK: Home dashboard

    /// Landing screen: usage at a glance, your council, quick-start presets, recent sessions.
    /// Entering the roundtable happens via New Directive, a preset, or a recent session.
    private var homeDashboard: some View {
        HStack(spacing: 10) {
            // Everything fits in one glance — no scrolling. Hero on top, then three equal-height
            // rows of paired cards that share the remaining height.
            VStack(spacing: 10) {
                HomeHero { q in query = q; canvasMode = .panels; screen = .council }

                // Grid pairs cards at equal height per row (so no empty gap under the shorter card)
                // while each row stays its natural height — tight gaps, no greedy stretch.
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        dashCard("USAGE", fill: true) { usageTiles }
                        dashCard("SPEND", fill: true) { spendContent }
                    }
                    GridRow {
                        dashCard("YOUR COUNCIL", fill: true) { councilOverview }
                        dashCard("QUICK START", fill: true) { quickStartList }
                    }
                    GridRow {
                        dashCard("PROVIDERS", fill: true) { providersBoard }
                        dashCard("RECENT", fill: true) { recentList }
                    }
                }

                Spacer(minLength: 0)   // leftover height sits at the very bottom, not between rows
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(16)

            colorRail.frame(width: 32).padding(.trailing, 6)
        }
    }

    private var usageTiles: some View {
        HStack(spacing: 0) {
            statTile(String(format: "$%.2f", store.allTimeCostUSD), "total spent")
            statDivider
            statTile(String(format: "$%.2f", store.thisMonthCostUSD), "this month")
            statDivider
            statTile("\(store.sessions.count)", "sessions")
        }
        .padding(.vertical, 6)
    }

    /// A prettier SPEND card: a smooth gradient-filled area sparkline + a clean stat row.
    @ViewBuilder private var spendContent: some View {
        let costs = store.recentSessionCosts
        VStack(alignment: .leading, spacing: 12) {
            if costs.contains(where: { $0 > 0 }) {
                Chart {
                    ForEach(Array(costs.enumerated()), id: \.offset) { idx, c in
                        AreaMark(x: .value("n", idx), y: .value("cost", c))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(
                                colors: [Blue.ink.opacity(0.30), Blue.ink.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("n", idx), y: .value("cost", c))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Blue.ink.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 52)
            } else {
                Text("No spend yet — your sessions will chart here.")
                    .font(Blue.mono(10)).foregroundStyle(Blue.dim)
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 52)
            }
            HStack(spacing: 0) {
                miniStat("\(store.thisWeekSessions)", "this week")
                Spacer(minLength: 8)
                miniStat(String(format: "$%.2f", store.avgCostPerSession), "avg / session")
                Spacer(minLength: 8)
                miniStat(store.topModelName ?? "—", "top model")
            }
        }
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink).lineLimit(1)
            Text(label).font(Blue.mono(8)).tracking(1).foregroundStyle(Blue.dim)
        }
    }

    private func priceLabel(_ p: LLMProvider) -> String {
        p.requiresAPIKey ? String(format: "$%g/$%g", p.pricePer1MInput, p.pricePer1MOutput) : "free"
    }

    private var providersBoard: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                  alignment: .leading, spacing: 4) {
            ForEach(LLMProvider.selectable) { p in
                Button { showSettings = true } label: {
                    HStack(spacing: 7) {
                        Circle().fill(store.keyExists(p) ? Blue.ink : Color.clear)
                            .overlay(Circle().strokeBorder(Blue.glassStroke))
                            .frame(width: 6, height: 6)
                        Text(p.panelName).font(Blue.mono(9, .bold)).foregroundStyle(Blue.ink).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(priceLabel(p)).font(Blue.mono(8)).foregroundStyle(Blue.dim).lineLimit(1)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 7)
                    .glassHover(corner: 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Vertical strip of background-tint swatches on the right edge. ~6 show at once and the NEXT
    /// one peeks at the bottom under a soft dark fade (+ a bobbing chevron over it), so it's obvious
    /// there are more colors to scroll to. Page stays clean.
    /// The agreed look: a thin vertical rail, ~7 swatches visible, the rest scroll (the next one
    /// peeks at the bottom edge). Smooth now that key-status no longer hits the Keychain per render.
    private var colorRail: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Blue.bgTints.indices, id: \.self) { i in
                        ColorSwatch(index: i, dot: 18, cell: 28, selected: bgTintIndex == i) {
                            withAnimation(.easeInOut(duration: 0.25)) { bgTintIndex = i }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 224)   // ~7 swatches; rest scroll, next peeks at the cut edge
            Spacer(minLength: 0)
        }
    }

    private func dashCard<Content: View>(_ title: String, fill: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.dim)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        // When fill, the card's GLASS BACKGROUND itself stretches to the row height (so paired cards
        // are equal with no empty gap under the shorter one) — the stretch is applied BEFORE the
        // glass, not after, which was the bug that left a blank band below the card.
        .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
        .glassPanel(corner: 20)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(Blue.mono(20, .bold)).foregroundStyle(Blue.ink)
            Text(label).font(Blue.mono(9)).tracking(1).foregroundStyle(Blue.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Blue.glassStroke).frame(width: 1, height: 30)
    }

    private func tokenString(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    private func personaLabel(_ seat: Seat) -> String {
        switch seat.id {
        case 0: return "Analyst"
        case 1: return "Practitioner"
        case 2: return "Skeptic"
        default: return "Seat \(seat.id + 1)"
        }
    }

    private func personaDescriptor(_ seat: Seat) -> String {
        switch seat.id {
        case 0: return "reasons from first principles"
        case 1: return "grounded in what works in practice"
        case 2: return "challenges the easy answer"
        default: return "your custom advisor"
        }
    }

    private var councilOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.seats) { seat in
                HStack(alignment: .center, spacing: 10) {
                    Circle().fill(store.hasKey(seat) ? Blue.ink : Color.clear)
                        .overlay(Circle().strokeBorder(Blue.glassStroke))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(personaLabel(seat).uppercased()).font(Blue.mono(10, .bold)).foregroundStyle(Blue.ink)
                            Text(personaDescriptor(seat)).font(Blue.body(10)).foregroundStyle(Blue.dim).lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(seat.provider?.panelName ?? "Not set")
                                .font(Blue.mono(9)).foregroundStyle(seat.provider == nil ? Blue.dim : Blue.sub)
                            if seat.provider != nil, !seat.model.isEmpty {
                                Text("·").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                                Text(seat.model).font(Blue.mono(9)).foregroundStyle(Blue.dim).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            Button(action: { showSettings = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 9, weight: .bold))
                    Text("CONFIGURE").font(Blue.mono(9, .bold)).tracking(1)
                }
                .foregroundStyle(Blue.sub)
                .padding(.vertical, 6).padding(.horizontal, 9)
                .glassHover(corner: 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
    }

    private var quickStartList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(CouncilConfig.presets.enumerated()), id: \.offset) { _, preset in
                Button(action: {
                    store.applyConfig(preset); store.newSession(); canvasMode = .panels; screen = .council
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name).font(Blue.mono(10, .bold)).foregroundStyle(Blue.ink)
                        Text(preset.detail ?? "").font(Blue.body(10)).foregroundStyle(Blue.dim).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .glassHover(corner: 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentList: some View {
        Group {
            if store.sessions.isEmpty {
                Text("No sessions yet — pick a question from the hero above to begin.")
                    .font(Blue.mono(10)).foregroundStyle(Blue.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 4) {
                    ForEach(store.sessions.prefix(4)) { s in
                        Button(action: { store.openSession(s); canvasMode = .panels; screen = .council }) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 10) {
                                    Text(s.title.isEmpty ? "Untitled" : s.title)
                                        .font(Blue.mono(11, .bold)).foregroundStyle(Blue.ink).lineLimit(1)
                                    Spacer()
                                    Text(relativeDate(s.updatedAt)).font(Blue.mono(9)).foregroundStyle(Blue.dim)
                                    Text(String(format: "$%.2f", s.totalCostUSD))
                                        .font(Blue.mono(9)).foregroundStyle(Blue.sub)
                                        .frame(width: 46, alignment: .trailing)
                                }
                                Text(sessionPreview(s))
                                    .font(Blue.body(10)).foregroundStyle(Blue.dim)
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 7).padding(.horizontal, 10)
                            .glassHover(corner: 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// A one-line preview of a session — its first advisor answer (or the question if none yet).
    private func sessionPreview(_ s: Session) -> String {
        for r in s.rounds {
            for a in r.answers.values where !a.isEmpty {
                return String(a.prefix(100)).replacingOccurrences(of: "\n", with: " ")
            }
            if !r.question.isEmpty { return r.question }
        }
        return "—"
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    private var mainCanvas: some View {
        VStack(spacing: layout.canvasRowGap) {
            if store.roundCount > 0 { roundNavigator }
            Group {
                switch canvasMode {
                case .panels:
                    panelGrid
                case .divergence:
                    deliberationView(title: "DIVERGENCE",
                                     text: store.divergenceText,
                                     loading: store.deliberationBusy && store.divergenceText == nil,
                                     canGenerate: store.canSynthesize,
                                     error: store.divergenceError,
                                     disabledReason: deliberationDisabledReason,
                                     onExportImage: { copy in exportImage(title: "DIVERGENCE", text: store.divergenceText, copy: copy) },
                                     onGenerate: { runRound { await store.runDivergence() } })
                case .synthesis:
                    deliberationView(title: "SYNTHESIS",
                                     text: store.synthesisText,
                                     loading: store.deliberationBusy && store.synthesisText == nil,
                                     canGenerate: store.canSynthesize,
                                     error: store.synthesisError,
                                     disabledReason: deliberationDisabledReason,
                                     onExportImage: { copy in exportImage(title: "SYNTHESIS", text: store.synthesisText, copy: copy) },
                                     onGenerate: { runRound { await store.runSynthesis() } })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            directiveInput
        }
        .padding(.horizontal, 4).padding(.top, 2).padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelGrid: some View {
        // Each panel is locked to exactly one-third of the available width. Without this, a seat
        // whose content has a wide intrinsic size (the model picker) would stretch its column and
        // push the whole window wider — so columns must never size to their content.
        GeometryReader { geo in
            let gap: CGFloat = layout.panelGap
            let colWidth = max(0, (geo.size.width - gap * 2) / 3)   // 2 gaps
            HStack(alignment: .top, spacing: gap) {
                ForEach(store.seats) { seat in
                    let hovered = hoveredSeat == seat.id

                    AdvisorPanel(seat: seat,
                                 answeredProvider: store.viewedAnswerProvider(seat.id),
                                 answer: store.viewedAnswer(seat.id),
                                 peerReview: store.viewedPeerReview(seat.id),
                                 loading: store.generatingRound == store.viewingRound && store.status[seat.id] == .loading,
                                 failedMessage: panelFailure(seat.id),
                                 connected: connected(seat),
                                 canRegenerate: store.isViewingLatest,
                                 isAdversary: store.devilsAdvocateSeatID == seat.id,
                                 onValidateKey: { await store.validateAndSaveKey($0, for: seat) },
                                 onSetModel: { store.setModel($0, seatID: seat.id) },
                                 onPickProvider: { pickProvider($0, for: seat) },
                                 onResetSeat: { store.clearProvider(seatID: seat.id) },
                                 onRegenerate: { runRound { await store.regenerate(seatID: seat.id) } })
                        .frame(width: colWidth, height: geo.size.height)   // all three equal height
                        .glassPanel(corner: layout.panelCorner, strokeOpacity: hovered ? 2.2 : 1)
                        .contentShape(Rectangle())   // hover only registers over the panel's own rect
                        .onHover { hoveredSeat = $0 ? seat.id : (hoveredSeat == seat.id ? nil : hoveredSeat) }
                        .id(seat.id)   // bind the panel's @State (begun/justPicked) to its seat
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Same model on two seats?",
               isPresented: Binding(get: { pendingPick != nil }, set: { if !$0 { pendingPick = nil } }),
               presenting: pendingPick) { pick in
            Button("Continue") { store.setProvider(pick.provider, seatID: pick.seatID); pendingPick = nil }
            Button("Cancel", role: .cancel) { pendingPick = nil }
        } message: { pick in
            Text("\(pick.provider.panelName) is already on another seat. Running it twice spends extra tokens and usually reduces divergence.")
        }
    }

    /// Assign a provider to a seat, warning first if the provider is already used elsewhere.
    private func pickProvider(_ provider: LLMProvider, for seat: Seat) {
        if store.providerInUse(provider, excluding: seat.id) {
            pendingPick = PendingPick(provider: provider, seatID: seat.id)
        } else {
            store.setProvider(provider, seatID: seat.id)
        }
    }

    private func panelFailure(_ id: Int) -> String? {
        guard store.isViewingLatest, case .failed(let m) = store.status[id] ?? .idle else { return nil }
        return m
    }

    /// Navigate between rounds; shows which round (and its question) you're viewing.
    private var roundNavigator: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Button { store.prevRound() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(store.canGoPrevRound ? Blue.ink : Blue.dim)
                        .frame(width: 28, height: 26)
                        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Blue.glassStroke.opacity(store.canGoPrevRound ? 1 : 0.4), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!store.canGoPrevRound)
                .accessibilityLabel("Previous round")

                Button { store.nextRound() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(store.canGoNextRound ? Blue.ink : Blue.dim)
                        .frame(width: 28, height: 26)
                        .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Blue.glassStroke.opacity(store.canGoNextRound ? 1 : 0.4), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!store.canGoNextRound)
                .accessibilityLabel("Next round")
            }

            Text("ROUND \(store.viewingRound + 1) / \(store.roundCount)")
                .font(Blue.mono(10, .bold)).tracking(1).foregroundStyle(Blue.ink)
            if store.divergenceText?.isEmpty == false { roundTag("DIV").help("This round has a divergence") }
            if store.synthesisText?.isEmpty == false { roundTag("SYN").help("This round has a synthesis") }
            Text(store.viewedQuestion)
                .font(Blue.mono(10)).foregroundStyle(Blue.sub).lineLimit(1).truncationMode(.tail)
            Spacer()
            exportMenu.offset(y: layout.exportY)   // EXPORT can be nudged independently
        }
        // offset (not padding) so moving this row never pushes the panels — they stay put.
        .offset(y: layout.roundBarTop)
    }

    /// A quiet outlined chip marking that the viewed round already has this artifact (DIV / SYN).
    private func roundTag(_ s: String) -> some View {
        Text(s).font(Blue.mono(8, .bold)).tracking(1).foregroundStyle(Blue.ink)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Blue.glassStroke, lineWidth: 1))
    }

    /// Full-width, calm reading view for the VIEWED round's cross-model artifact.
    /// Shows the stored artifact if present (never auto-regenerates); offers an explicit
    /// GENERATE for rounds that don't have one yet, and a REGENERATE in the header.
    private func deliberationView(title: String, text: String?, loading: Bool,
                                  canGenerate: Bool, error: String?, disabledReason: String,
                                  onExportImage: @escaping (Bool) -> Void,
                                  onGenerate: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(Blue.mono(15, .bold)).tracking(2).foregroundStyle(Blue.ink)
                if let n = store.synthesizerName, text != nil {
                    Text("· via \(n.uppercased())").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                }
                if let error, !loading {
                    Text("⚠︎ \(error)").font(Blue.mono(9)).foregroundStyle(Blue.red)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer()
                if text != nil && !loading {
                    Button(action: onGenerate) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                            Text("REGENERATE").font(Blue.mono(9, .bold)).tracking(1)
                        }
                        .foregroundStyle(Blue.sub).padding(.horizontal, 8).padding(.vertical, 5)
                        .glassHover(corner: 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!canGenerate).help("Regenerate for this round")
                }
                if text != nil && !loading {
                    Menu {
                        Button("Save image…") { onExportImage(false) }
                        Button("Copy image") { onExportImage(true) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "photo").font(.system(size: 9, weight: .bold))
                            Text("IMAGE").font(Blue.mono(9, .bold)).tracking(1)
                        }
                        .foregroundStyle(Blue.sub).padding(.horizontal, 8).padding(.vertical, 5)
                        .glassHover(corner: 8).contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Export this as a shareable image")
                    .accessibilityLabel("Export as image")
                }
                Button { canvasMode = .panels } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left").font(.system(size: 10, weight: .bold))
                        Text("PANELS").font(Blue.mono(10, .bold)).tracking(1)
                    }
                    .foregroundStyle(Blue.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Blue.glassFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .overlay(alignment: .bottom) { Rectangle().fill(Blue.glassStroke).frame(height: 1) }

            if loading {
                VStack(spacing: 12) {
                    Text("DELIBERATING…").font(Blue.mono(11, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    FillBar(once: true).frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let text, !text.isEmpty {
                ScrollView {
                    MarkdownView(text: text, baseSize: 15)
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
            } else {
                VStack(spacing: 14) {
                    Text("Not generated for this round yet.")
                        .font(Blue.body(14)).foregroundStyle(Blue.sub)
                    Button(action: onGenerate) {
                        Text("GENERATE \(title)").font(Blue.mono(11, .bold)).tracking(1)
                            .foregroundStyle(canGenerate ? Blue.ink : Blue.dim)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .background(canGenerate ? Blue.glassBright : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Blue.glassStroke, lineWidth: 1))
                            .shadow(color: Color.adaptive(.clear, .white.opacity(canGenerate ? 0.06 : 0)), radius: 12)
                    }
                    .buttonStyle(.plain).disabled(!canGenerate)
                    if !canGenerate {
                        Text(disabledReason)
                            .font(Blue.mono(9)).foregroundStyle(Blue.dim)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(corner: 22)
    }

    private func connected(_ seat: Seat) -> Bool {
        _ = store.keyRevision
        return store.hasKey(seat)
    }

    /// Divergence/Synthesis can be viewed if already generated, or run once ≥2 advisors answered.
    private var divergenceAvailable: Bool { store.canSynthesize || store.divergenceText != nil }
    private var synthesisAvailable: Bool { store.canSynthesize || store.synthesisText != nil }

    /// Why GENERATE is disabled — distinguishes "busy elsewhere" from "needs ≥2 answers".
    private var deliberationDisabledReason: String {
        store.isWorking ? "A generation is in progress — wait for it to finish."
                        : "Answer ≥2 advisors in this round first."
    }

    private var directiveInput: some View {
      VStack(alignment: .trailing, spacing: 6) {
        // Quiet session usage readout, right-aligned just above the input pill.
        if store.sessionInputTokens + store.sessionOutputTokens > 0 {
            HStack(spacing: 6) {
                Image(systemName: "bolt").font(.system(size: 8, weight: .bold))
                Text("\(tokenString)").font(Blue.mono(9))
                Text("·").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                Text("~\(costString)").font(Blue.mono(9))
            }
            .foregroundStyle(Blue.sub)
            .padding(.trailing, 6)
            .help("Session tokens · estimated cost (you pay providers directly)")
        }

        VStack(alignment: .leading, spacing: 12) {
            if let img = pickedImage {
                HStack(spacing: 10) {
                    Button { showImagePreview = true } label: {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 46).clipped()
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Blue.paper)
                                    .padding(2).background(Blue.ink)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Enlarge")
                    .accessibilityLabel("Enlarge attached image")
                    Text("IMAGE ATTACHED").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    Button { pickedImage = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                            .frame(width: 22, height: 22).overlay(Rectangle().stroke(Blue.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove attached image")
                    Spacer()
                }
            }

            HStack(spacing: 14) {
                Button(action: pickImage) {
                    Image(systemName: "photo").font(.system(size: 15)).foregroundStyle(Blue.sub)
                        .frame(width: 30, height: 30)
                        .glassHover(corner: 15)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach image")
                .accessibilityLabel("Attach image")
                ComposerTextView(text: $query, placeholder: "Enter a command or prompt…",
                                 onSubmit: ask, onPasteImage: { pickedImage = $0 })
                    .frame(maxWidth: .infinity)
                    .frame(height: composerHeight)
                Button(action: isBusy ? stop : ask) {
                    Image(systemName: isBusy ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isBusy ? Blue.red : (canAsk ? Blue.ink : Blue.dim))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(Blue.glassBright, in: Circle())
                        .overlay(Circle().strokeBorder(Blue.glassStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!isBusy && !canAsk)
                .accessibilityLabel(isBusy ? "Stop" : "Execute")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Blue.glassBright, in: Capsule())
        .overlay(Capsule().strokeBorder(isDropTargeted ? Blue.ink.opacity(0.4) : Blue.glassStroke,
                                        lineWidth: isDropTargeted ? 2 : 1))
        .shadow(color: Color.adaptive(.black.opacity(0.10), .white.opacity(0.08)), radius: 20, y: 6)
        .shadow(color: .black.opacity(0.30), radius: 16, y: 10)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleImageDrop(providers)
        }
      }
      .sheet(isPresented: $showImagePreview) {
            imagePreviewSheet.preferredColorScheme(scheme)
      }
    }

    @ViewBuilder private var imagePreviewSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ATTACHED IMAGE").font(Blue.mono(11, .bold)).tracking(2).foregroundStyle(Blue.ink)
                Spacer()
                Button { showImagePreview = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Blue.ink)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                        .contentShape(Rectangle())
                        .cursorGlow()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close image preview")
            }
            .padding(20)
            Rectangle().fill(Blue.glassStroke).frame(height: 1)

            if let img = pickedImage {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            } else {
                Text("No image.").font(Blue.body(14)).foregroundStyle(Blue.sub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 680, height: 560)
        .background(Blue.bg)
    }

    private var canAsk: Bool {
        (!query.trimmingCharacters(in: .whitespaces).isEmpty || pickedImage != nil) && !isAsking
    }

    private var tokenString: String {
        let t = store.sessionInputTokens + store.sessionOutputTokens
        return t >= 1000 ? String(format: "%.1fK tok", Double(t) / 1000) : "\(t) tok"
    }
    private var costString: String { String(format: "$%.4f", store.sessionCostUSD) }

    /// Composer grows with explicit newlines, 1→6 lines, then scrolls internally.
    private var composerHeight: CGFloat {
        let lines = max(1, query.components(separatedBy: "\n").count)
        return CGFloat(min(6, lines)) * 18 + 5
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            pickedImage = img
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage {
                    DispatchQueue.main.async { pickedImage = img }
                }
            }
            return true
        }
        return false
    }

    /// Re-encode the attached NSImage to PNG bytes for the API request.
    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func ask() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!q.isEmpty || pickedImage != nil), !isBusy else { return }
        let image: ImageAttachment? = pickedImage
            .flatMap(pngData(from:))
            .map { ImageAttachment(data: $0, mediaType: "image/png") }
        canvasMode = .panels
        isAsking = true
        query = ""
        pickedImage = nil
        runningTask = Task {
            await store.ask(q, image: image)
            isAsking = false
            runningTask = nil
        }
    }

    /// Anything running right now (any advisor loading, a deliberation round, or a tracked task).
    private var isBusy: Bool {
        runningTask != nil || store.deliberationBusy || store.status.values.contains { $0 == .loading }
    }

    /// Stop the in-flight round and return loading advisors to idle.
    private func stop() {
        runningTask?.cancel()
        runningTask = nil
        store.cancelAll()
        isAsking = false
    }

    /// Run a deliberation round as the cancellable in-flight task.
    private func runRound(_ op: @escaping () async -> Void) {
        runningTask = Task { await op(); runningTask = nil }
    }

    /// Render a deliberation artifact to a shareable PNG (current theme) and save it or copy it.
    private func exportImage(title: String, text: String?, copy: Bool) {
        guard let text, !text.isEmpty else { return }
        let card = ShareCard(title: title, via: store.synthesizerName,
                             question: store.viewedQuestion, markdown: text,
                             watermark: shareWatermark)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        if copy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        } else {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "council-\(title.lowercased()).png"
            panel.allowedContentTypes = [.png]
            if panel.runModal() == .OK, let url = panel.url { try? png.write(to: url) }
        }
    }
}

// MARK: - Sidebar mode row

/// One sidebar deliberation row (ROUNDTABLE / PEER REVIEW / …). Active or hovered → a glass pill;
/// the pill geometry is identical in both states so borders never mismatch.
private struct ModeRow: View {
    enum ModeState { case active, locked, button }
    let icon: String
    let label: String
    let state: ModeState
    var hint: String?
    var action: (() -> Void)?
    @State private var hovered = false

    private var active: Bool { state == .active }
    private var locked: Bool { state == .locked }

    var body: some View {
        let showPill = active || (hovered && action != nil && !locked)
        let row = HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15))
            Text(label).font(Blue.mono(11, .bold)).tracking(1)
            Spacer()
            if locked { Image(systemName: "lock.fill").font(.system(size: 9)) }
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .foregroundStyle(locked ? Blue.dim : Blue.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Blue.glassBright))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                .opacity(showPill ? 1 : 0)
        }
        // Generous outer inset so adjacent highlighted pills keep a clear gap (no collision).
        .padding(.horizontal, 12).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isOver in
            guard action != nil else { return }
            withAnimation(.easeOut(duration: 0.18)) { hovered = isOver }
        }
        .help(hint ?? (locked ? "Not built yet — on the roadmap"
                              : (state == .button ? "Settings" : "Active mode: all models answer in parallel")))

        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

// MARK: - Advisor panel

private struct AdvisorPanel: View {
    let seat: Seat
    /// Provider name stored with this round's answer (used for the title when the seat is unassigned).
    var answeredProvider: String? = nil
    let answer: String?
    let peerReview: String?
    let loading: Bool
    let failedMessage: String?
    let connected: Bool
    let canRegenerate: Bool
    let isAdversary: Bool
    let onValidateKey: (String) async -> String?   // returns nil on success, else an error message
    let onSetModel: (String) -> Void
    let onPickProvider: (LLMProvider) -> Void
    let onResetSeat: () -> Void
    let onRegenerate: () -> Void

    @State private var keyDraft = ""
    @State private var validating = false
    @State private var keyError: String?
    /// True only after the user picks a provider / enters a key this session — gates the
    /// model-selection step so returning users (already set up) go straight to ready.
    @State private var justPicked = false
    /// Set once the user confirms the model with BEGIN.
    @State private var begun = false
    @State private var panelHover = false

    private var hasAnswer: Bool { answer?.isEmpty == false }
    private var failed: Bool { failedMessage != nil }
    /// The model-selection step: after a provider is picked, before BEGIN. Comes BEFORE the key
    /// step so the user chooses a model first, then (if needed) enters a key.
    private var showingModelPicker: Bool {
        seat.provider != nil && justPicked && !begun && !hasAnswer && !loading && !failed
    }

    /// Conversation underway → shrink the header to give the answer room.
    private var hasConversation: Bool { hasAnswer || loading || failed }

    private var statusText: String {
        if seat.provider == nil { return "NO MODEL SELECTED" }
        if !connected { return "OFFLINE — KEY REQUIRED" }
        if loading { return "PROCESSING" }
        if failed { return "ERROR" }
        return hasAnswer ? "ACTIVE" : "STANDBY"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.top, 18)

            DashLine().stroke(Blue.glassStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1).padding(.vertical, hasConversation ? 8 : 12)

            statusLine
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.22), value: hasConversation)
        .onHover { panelHover = $0 }
        // A provider actually got assigned (covers both direct pick and the dup-warning Continue)
        // → advance to the SELECT MODEL step. Clearing it (reset → nil) drops back to the picker.
        .onChange(of: seat.provider) { _, newValue in
            justPicked = (newValue != nil)
            if newValue == nil { begun = false }
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text((seat.provider?.panelName ?? answeredProvider ?? "—").uppercased())
                    .font(Blue.mono(hasConversation ? 13 : 18, .bold)).tracking(1).foregroundStyle(Blue.ink)
                    .lineLimit(1).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                if connected && !showingModelPicker { modelMenu }
                if isAdversary {
                    Text("ADVERSARY").font(Blue.mono(7, .bold)).tracking(2).foregroundStyle(Blue.dim)
                        .help("Devil's advocate — attacks the consensus in peer review")
                }
            }
            Spacer()
            if seat.provider != nil && !hasConversation {
                Button {
                    // onResetSeat clears the provider → the onChange(of: seat.provider) handler
                    // resets begun/justPicked. We only clear the key-entry scratch state here.
                    keyError = nil; keyDraft = ""
                    onResetSeat()
                } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 11)).foregroundStyle(Blue.sub)
                        .frame(width: 26, height: 26)
                        .glassHover(corner: 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change model — back to picker")
                .accessibilityLabel("Change model")
            }
        }
        .padding(.bottom, hasConversation ? 8 : 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Blue.glassStroke).frame(height: 1) }
    }

    /// Small, quiet menu showing the active model id — transparency, and change it anytime.
    private var modelMenu: some View {
        Menu {
            ForEach(seat.provider?.modelOptions ?? [], id: \.self) { m in
                Button { onSetModel(m) } label: {
                    if m == seat.model { Label(m, systemImage: "checkmark") } else { Text(m) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(seat.model).font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).foregroundStyle(Blue.sub)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Change this seat's model")
        .accessibilityLabel("Change model")
    }

    /// Status accent color drives the pill + text tint.
    private var statusColor: Color {
        if failed { return Blue.red }
        if loading { return Blue.accent }
        if hasAnswer { return Blue.ok }
        if seat.provider == nil || !connected { return Blue.dim }
        return Blue.warn   // standby
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.8), radius: loading ? 4 : 2)
            Text(statusText)
                .font(Blue.mono(hasConversation ? 9 : 11, .bold))
                .foregroundStyle(statusColor)
            Spacer()
            if panelHover && canRegenerate && (hasAnswer || failed) && !loading {
                Button(action: onRegenerate) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold))
                        Text(failed ? "RETRY" : "REGEN").font(Blue.mono(8, .bold)).tracking(1)
                    }
                    .foregroundStyle(failed ? Blue.red : Blue.sub).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(failed ? "Retry this advisor" : "Regenerate this advisor's answer")
                .accessibilityLabel(failed ? "Retry advisor" : "Regenerate advisor")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if hasAnswer || loading || failed {
            answerView   // a conversation (incl. a loaded session's answers) always wins over setup
        } else if seat.provider == nil {
            providerPickerView           // 1. pick provider
        } else if showingModelPicker {
            modelSelectionView           // 2. pick model (then BEGIN)
        } else if !connected {
            keyEntryView                 // 3. key — only if BEGIN found this provider needs one
        } else {
            Text("Awaiting directive.")
                .font(Blue.body(15)).italic().foregroundStyle(Blue.sub)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Shown right after a provider is picked: pick a model, then BEGIN to confirm.
    private var modelSelectionView: some View {
        let options = seat.provider?.modelOptions ?? []
        return VStack(alignment: .leading, spacing: 14) {
            Text("SELECT MODEL").font(Blue.mono(11, .bold)).tracking(2).foregroundStyle(Blue.sub)
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element) { idx, m in
                    Button { onSetModel(m) } label: {
                        HStack {
                            Text(m).font(Blue.mono(12)).foregroundStyle(Blue.ink)
                            Spacer()
                            if m == seat.model {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                            }
                        }
                        .padding(.vertical, 10).padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(m == seat.model ? Blue.glassBright : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx < options.count - 1 {
                        Rectangle().fill(Blue.glassStroke).frame(height: 1)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))

            HStack {
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.2)) { begun = true } } label: {
                    HStack(spacing: 6) {
                        // If the chosen provider needs a key we don't have yet, BEGIN leads to key entry.
                        Text(connected ? "BEGIN" : "CONTINUE").font(Blue.mono(11, .bold)).tracking(1)
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Blue.paper)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Blue.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 300)
    }

    private var answerView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let answer, !answer.isEmpty {
                        MarkdownView(text: answer).textSelection(.enabled)
                    }
                    if let peerReview, !peerReview.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Rectangle().fill(Blue.ink).frame(width: 16, height: 2)
                                Text("PEER REVIEW").font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.sub)
                            }
                            MarkdownView(text: peerReview).textSelection(.enabled)
                        }
                        .padding(.top, 6)
                    }
                    if loading {
                        HStack(spacing: 0) { StreamingCaret(); Spacer(minLength: 0) }
                    }
                    if let failedMessage {
                        Text("! " + failedMessage).font(Blue.mono(11)).foregroundStyle(Blue.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
            }
            .onChange(of: answer) { _, _ in scrollToEnd(proxy) }
            .onChange(of: peerReview) { _, _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
    }

    /// First state of an empty seat: a box that opens on hover into the provider list.
    private var providerPickerView: some View {
        ProviderPicker(onPick: pick)
    }

    /// Key entry — reached only after a model is chosen and BEGIN finds the provider needs a key.
    private var keyEntryView: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("> ENTER YOUR API KEY").font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink)
            MaskedKeyField(text: $keyDraft, onSubmit: submitKey)
                .frame(height: 18)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                .disabled(validating)
                .opacity(validating ? 0.5 : 1)
            if validating {
                VStack(spacing: 6) {
                    Text("VALIDATING…").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    FillBar(once: true)
                }
            } else if let keyError {
                Text(keyError).font(Blue.mono(10)).foregroundStyle(Blue.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 280)
    }

    private func pick(_ provider: LLMProvider) {
        // Reset the per-step flags, then let the parent assign. We do NOT set justPicked here —
        // a duplicate-provider pick may be cancelled in the alert, so justPicked must follow the
        // ACTUAL assignment (onModelStepReady), never the click.
        begun = false; keyError = nil; keyDraft = ""
        onPickProvider(provider)
    }

    private func submitKey() {
        let k = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !validating else { return }
        validating = true
        keyError = nil
        Task {
            let error = await onValidateKey(k)   // tiny test call; saves only if it works
            validating = false
            if let error {
                keyError = error                 // invalid / no balance → stay, show why
            } else {
                keyDraft = ""                    // wipe in-memory draft
                begun = true                     // key valid → seat is ready (model already chosen)
            }
        }
    }
}

// MARK: - Provider picker (hover-to-open box)

/// A compact box that opens on HOVER (not click) into the provider list: ~2 options show fully,
/// the next fades into fog at the bottom edge, and the rest is reachable by scrolling.
private struct ProviderPicker: View {
    let onPick: (LLMProvider) -> Void
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(Blue.ink).frame(width: 14, height: 2)
                Text("PICK YOUR MODEL").font(Blue.mono(11, .bold)).tracking(3).foregroundStyle(Blue.sub)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Blue.sub)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .contentShape(Rectangle())

            if open {
                Rectangle().fill(Blue.ink.opacity(0.2)).frame(height: 1)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(LLMProvider.selectable.enumerated()), id: \.element) { idx, prov in
                            ProviderCard(provider: prov, index: idx) { onPick(prov) }
                        }
                    }
                    .padding(12)
                }
                .frame(height: 168)   // ~2 cards + a foggy peek of the 3rd
                .mask(                 // fade the bottom edge into "fog" → signals scroll
                    LinearGradient(stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.74),
                        .init(color: .clear, location: 1.0)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 320)   // cap, but shrink to fit a narrow column instead of forcing it wider
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Blue.glassBright, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(open ? Blue.glassStroke.opacity(2) : Blue.glassStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { h in withAnimation(.easeInOut(duration: 0.26)) { open = h } }
    }
}

// MARK: - Provider card (animated tile in "PICK YOUR MODEL")

/// One provider tile: staggered fade/slide-in entrance, cursor-glow + lift + sliding arrow on hover.
private struct ProviderCard: View {
    let provider: LLMProvider
    let index: Int
    let action: () -> Void
    @State private var hovered = false
    @State private var shown = false

    /// Every card gets a one-word descriptor (uses the provider note, else a type hint).
    private var note: String {
        if let n = provider.pickerNote { return n }
        switch provider {
        case .claude, .openAI, .gemini: return "frontier"
        case .grok:    return "contrarian"
        case .mistral: return "open-weight"
        default:       return ""
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.panelName.uppercased())
                        .font(Blue.mono(13, .bold)).tracking(1).foregroundStyle(Blue.ink)
                    if !note.isEmpty {
                        Text(note.uppercased()).font(Blue.mono(8, .bold)).tracking(1).foregroundStyle(Blue.sub)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(hovered ? Blue.ink : Blue.dim)
                    .offset(x: hovered ? 4 : 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(hovered ? Blue.glassBright : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Blue.glassStroke, lineWidth: hovered ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.015 : 1)
        .onHover { h in withAnimation(.easeOut(duration: 0.16)) { hovered = h } }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 12)
        .onAppear {
            withAnimation(.easeOut(duration: 0.34).delay(Double(index) * 0.045)) { shown = true }
        }
    }
}

// MARK: - Masked key field (plain NSTextField + manual masking → NO AutoFill popup)

/// macOS shows the "Passwords…" AutoFill popover for ANY `NSSecureTextField`, and there
/// is no public API to suppress it. So we do NOT use a secure field. Instead this is a
/// plain `NSTextField` that only ever *displays* bullets; the real characters live solely
/// in the bound @State (wiped right after they're handed to the Keychain). Because it is a
/// plain field, macOS does not treat it as a credential field — so no AutoFill popover.
///
/// Trade-off vs. NSSecureTextField: we lose the OS "secure input" keystroke isolation.
/// For a local BYO-keys app that's an acceptable cost; the key is still masked on screen,
/// never written to disk/UserDefaults, never logged, and goes straight to the Keychain.
private struct MaskedKeyField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "paste key, press enter"
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = .labelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingHead
        field.delegate = context.coordinator
        field.cell?.sendsActionOnEndEditing = false
        field.stringValue = String(repeating: "•", count: text.count)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let target = String(repeating: "•", count: text.count)
        if nsView.stringValue != target { nsView.stringValue = target }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: MaskedKeyField
        init(_ parent: MaskedKeyField) { self.parent = parent }

        /// Reconstruct the real value from the edit, using the caret position so that
        /// inserts, pastes, and mid-string deletes all map to the right characters —
        /// then re-mask the field so only bullets are ever shown.
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let shown = Array(field.stringValue)
            let newLen = shown.count
            let oldLen = parent.text.count
            let caret = field.currentEditor()?.selectedRange.location ?? newLen
            var real = Array(parent.text)

            if newLen > oldLen {                       // insertion / paste
                let count = newLen - oldLen
                let start = max(caret - count, 0)
                let chars = Array(shown[start..<caret])
                real.insert(contentsOf: chars, at: min(start, real.count))
            } else if newLen < oldLen {                // deletion
                let count = oldLen - newLen
                let start = min(caret, real.count)
                let end = min(start + count, real.count)
                real.removeSubrange(start..<end)
            } else if let a = shown.firstIndex(where: { $0 != "•" }) {
                // same length: a selection was replaced — splice the typed run in place
                var b = a
                while b < shown.count, shown[b] != "•" { b += 1 }
                let chars = Array(shown[a..<b])
                let lo = min(a, real.count), hi = min(b, real.count)
                real.replaceSubrange(lo..<hi, with: chars)
            }

            let newReal = String(real)
            parent.text = newReal
            field.stringValue = String(repeating: "•", count: newReal.count)
            field.currentEditor()?.selectedRange = NSRange(location: min(caret, newReal.count), length: 0)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Plain text field (AppKit-backed, no AutoFill popup)

/// A normal (non-secure) text field backed by `NSTextField`. SwiftUI's `TextField`
/// triggers macOS's "Passwords…" AutoFill heuristic when programmatically focused;
/// a plain `NSTextField` does not. Used for the project name and the directive input.
private struct PlainTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var fontSize: CGFloat = 14
    var weight: NSFont.Weight = .regular
    var filter: ((String) -> String)? = nil
    var onSubmit: () -> Void = {}
    /// If set, pasting (⌘V) an image into the field hands the image here instead of
    /// pasting text. Text pastes still work normally.
    var onPasteImage: ((NSImage) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> PasteAwareTextField {
        let field = PasteAwareTextField()
        field.placeholderString = placeholder
        field.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        field.textColor = .labelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.cell?.sendsActionOnEndEditing = false
        field.onPasteImage = onPasteImage
        return field
    }

    func updateNSView(_ nsView: PasteAwareTextField, context: Context) {
        nsView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        nsView.onPasteImage = onPasteImage
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PlainTextField
        init(_ parent: PlainTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            var value = field.stringValue
            if let filter = parent.filter {
                let cleaned = filter(value)
                if cleaned != value { field.stringValue = cleaned; value = cleaned }
            }
            parent.text = value
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// An `NSTextField` that intercepts an image paste (⌘V). Paste of an `NSTextField` is
/// actually handled by the shared field editor, so we hook the ⌘V key equivalent: when
/// the field is being edited and the clipboard holds an image, capture it; otherwise fall
/// through so normal text paste still works.
final class PasteAwareTextField: NSTextField {
    var onPasteImage: ((NSImage) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let onPasteImage,
           currentEditor() != nil,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "v",
           let img = NSImage(pasteboard: NSPasteboard.general) {
            onPasteImage(img)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Multi-line composer (Enter sends, Shift+Enter newline)

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onPasteImage: ((NSImage) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> NSScrollView {
        let tv = PasteImageTextView()
        tv.delegate = context.coordinator
        tv.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.isRichText = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 2, height: 3)
        tv.allowsUndo = true
        tv.string = text
        tv.onPasteImage = onPasteImage
        tv.placeholderString = placeholder
        tv.textColor = .labelColor
        tv.identifier = NSUserInterfaceItemIdentifier("council.composer")

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? PasteImageTextView else { return }
        if tv.string != text { tv.string = text; tv.needsDisplay = true }
        tv.onPasteImage = onPasteImage
        tv.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ComposerTextView
        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                // Shift+Enter → newline; plain Enter → send.
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// NSTextView that captures an image paste and draws a placeholder when empty.
final class PasteImageTextView: NSTextView {
    var onPasteImage: ((NSImage) -> Void)?
    var placeholderString: String = ""

    override func paste(_ sender: Any?) {
        if let onPasteImage, let img = NSImage(pasteboard: .general) { onPasteImage(img); return }
        super.paste(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !placeholderString.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
            ]
            placeholderString.draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
                                   withAttributes: attrs)
        }
    }
}

// MARK: - Settings

/// Appearance + the (now editable) system prompt + where conversations are saved.
private struct SettingsSheet: View {
    @Bindable var store: CouncilStore
    @Binding var appearance: String
    var onClose: () -> Void

    /// Whether exported images carry the "made with Council" watermark. Default on (growth).
    @AppStorage("council.shareWatermark") private var shareWatermark = true
    /// Spend alert: notify once when all-time spend crosses this dollar threshold.
    @AppStorage("council.spendAlertOn") private var spendAlertOn = false
    @AppStorage("council.spendAlertAmt") private var spendAlertAmt = 10.0
    /// Mirror the chosen background tint so the sheet harmonizes with the app behind it.
    @AppStorage("council.bgTint") private var bgTintIndex = 0
    @AppStorage("council.liteMode") private var liteMode = false
    /// A council config staged for import, awaiting confirmation (it overwrites the live setup).
    @State private var pendingImport: CouncilConfig?
    /// A preset staged for "load" confirmation.
    @State private var pendingPreset: CouncilConfig?

    /// Settings categories shown in the left rail.
    enum Tab: String, CaseIterable, Identifiable {
        case models = "Models", deliberation = "Deliberation", councils = "Councils", app = "App"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .models: return "cube"
            case .deliberation: return "arrow.triangle.branch"
            case .councils: return "square.grid.2x2"
            case .app: return "gearshape"
            }
        }
    }
    @State private var tab: Tab = .models

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SETTINGS").font(Blue.serif(28)).foregroundStyle(Blue.ink).tracking(-0.5)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Blue.ink)
                        .frame(width: 32, height: 32)
                        .glassHover(corner: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close settings")
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)

            HStack(alignment: .top, spacing: 0) {
                // Left category rail.
                VStack(spacing: 4) {
                    ForEach(Tab.allCases) { t in
                        settingsTab(t)
                    }
                    Spacer()
                }
                .frame(width: 168)
                .padding(.horizontal, 12).padding(.top, 4)

                // Right content pane.
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch tab {
                        case .models:       modelsTab
                        case .deliberation: deliberationTab
                        case .councils:     councilsTab
                        case .app:          appTab
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 4).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 640, height: 600)
        .background {
            ZStack {
                LinearGradient(colors: [
                    Color.adaptive(Color(red: 0.96, green: 0.96, blue: 0.97), Color(red: 0.10, green: 0.10, blue: 0.105)),
                    Color.adaptive(Color(red: 0.92, green: 0.92, blue: 0.94), Color(red: 0.06, green: 0.06, blue: 0.065))
                ], startPoint: .top, endPoint: .bottom)
                // Harmonize with the app's chosen background tint (same hue recipe as the backdrop).
                if let s = Blue.tintStyle(bgTintIndex) {
                    Rectangle().fill(s).blendMode(.color).opacity(0.5)
                    Rectangle().fill(s).opacity(0.12)
                }
            }
        }
        .modifier(SettingsAlerts(store: store,
                                 pendingImport: $pendingImport, pendingPreset: $pendingPreset))
    }

    /// One row in the left category rail.
    private func settingsTab(_ t: Tab) -> some View {
        SettingsTabRow(tab: t, selected: tab == t) { tab = t }
    }

    // MARK: Grouped tabs

    @ViewBuilder private var modelsTab: some View {
        section("SYSTEM PROMPT — ALL MODELS") {
            promptEditor($store.sharedSystemPrompt, placeholder: "Shared instruction…", tall: true)
            Button { store.sharedSystemPrompt = CouncilStore.defaultSystemPrompt } label: {
                Text("RESET TO DEFAULT").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
            }
            .buttonStyle(.plain)
        }
        section("PER-MODEL PROMPT (OPTIONAL)") {
            Text("Leave empty to use the shared prompt.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
            ForEach(store.seats) { seat in
                promptEditor(seatBinding(seat),
                             placeholder: "— shared prompt —",
                             label: (seat.provider?.panelName ?? "Seat \(seat.id + 1)").uppercased())
            }
        }
        section("SAMPLING — PER MODEL (OPTIONAL)") {
            Text("Temperature trades focus for variety. Max tokens caps each reply. Leave on AUTO for the model's own default.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(store.seats) { seat in
                samplingControls(for: seat)
            }
        }
    }

    @ViewBuilder private var deliberationTab: some View {
        section("DIVERGENCE & SYNTHESIS MODEL") {
                        Text("These two are written by one model — it spends that provider's credit, and the analysis carries that model's lens.")
                            .font(Blue.body(11)).foregroundStyle(Blue.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 0) {
                            ForEach(Array(store.seats.enumerated()), id: \.element.id) { idx, seat in
                                Button { store.synthesizerSeatID = seat.id } label: {
                                    HStack {
                                        Text(seat.provider?.panelName ?? "Seat \(seat.id + 1)").font(Blue.mono(12)).foregroundStyle(Blue.ink)
                                        Spacer()
                                        if store.synthesizerSeatID == seat.id {
                                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                                        }
                                    }
                                    .padding(.vertical, 10).padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(store.synthesizerSeatID == seat.id ? Blue.glassBright : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if idx < store.seats.count - 1 {
                                    Rectangle().fill(Blue.glassStroke).frame(height: 1)
                                }
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    }

        section("DEVIL'S ADVOCATE") {
            Text("One advisor steelmans the emerging consensus, then attacks it — mandated dissent in peer review. Off by default.")
                .font(Blue.body(11)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                advocateRow(id: -1, label: "None")
                Rectangle().fill(Blue.glassStroke).frame(height: 1)
                ForEach(Array(store.seats.enumerated()), id: \.element.id) { idx, seat in
                    advocateRow(id: seat.id, label: seat.provider?.panelName ?? "Seat \(seat.id + 1)")
                    if idx < store.seats.count - 1 {
                        Rectangle().fill(Blue.glassStroke).frame(height: 1)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
        }
    }

    @ViewBuilder private var councilsTab: some View {
        section("COUNCILS") {
                        Text("A council is your seat lineup, personas, and sampling — saved as a shareable file. No API keys are included.")
                            .font(Blue.body(11)).foregroundStyle(Blue.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            councilButton("EXPORT…", filled: true) {
                                Exporter.saveCouncil(store.currentConfig(name: "My council"))
                            }
                            councilButton("IMPORT…", filled: false) {
                                if let c = Exporter.openCouncil() { pendingImport = c }
                            }
                        }
                        Text("PRESETS").font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.dim)
                            .padding(.top, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(CouncilConfig.presets.enumerated()), id: \.element.id) { idx, preset in
                                Button { pendingPreset = preset } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.name).font(Blue.mono(11, .bold)).foregroundStyle(Blue.ink)
                                            if let d = preset.detail {
                                                Text(d).font(Blue.body(10)).foregroundStyle(Blue.sub)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.down.circle").font(.system(size: 12)).foregroundStyle(Blue.sub)
                                    }
                                    .padding(.vertical, 9).padding(.horizontal, 11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if idx < CouncilConfig.presets.count - 1 {
                                    Rectangle().fill(Blue.glassStroke).frame(height: 1)
                                }
                            }
                        }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
        }
    }

    @ViewBuilder private var appTab: some View {
        section("APPEARANCE") {
            HStack(spacing: 0) {
                AppearanceOption(label: "LIGHT", value: "light", icon: "sun.max", appearance: $appearance)
                AppearanceOption(label: "DARK", value: "dark", icon: "moon", appearance: $appearance)
            }
        }
        section("PERFORMANCE") {
            Toggle(isOn: $liteMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reduce glass for performance")
                        .font(Blue.body(12)).foregroundStyle(Blue.ink)
                    Text("Uses a lighter material and an opaque window (no desktop-through). Turn on if scrolling feels heavy on your Mac.")
                        .font(Blue.mono(10)).foregroundStyle(Blue.dim)
                }
            }
            .toggleStyle(.switch).tint(Blue.accent)
        }
        section("SHARING") {
            Toggle(isOn: $shareWatermark) {
                Text("Show “made with Council” on exported images")
                    .font(Blue.body(12)).foregroundStyle(Blue.ink)
            }
            .toggleStyle(.switch).tint(Blue.accent)
        }
        section("SPEND ALERT") {
            Toggle(isOn: $spendAlertOn) {
                Text("Notify me once my total spend crosses a threshold")
                    .font(Blue.body(12)).foregroundStyle(Blue.ink)
            }
            .toggleStyle(.switch).tint(Blue.accent)
            .onChange(of: spendAlertOn) { _, on in
                if on {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
            }
            if spendAlertOn {
                HStack(spacing: 8) {
                    Text("Alert at").font(Blue.body(12)).foregroundStyle(Blue.sub)
                    Text("$").font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink)
                    TextField("10", value: $spendAlertAmt, format: .number)
                        .textFieldStyle(.plain)
                        .font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink)
                        .frame(width: 60)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.adaptive(.black.opacity(0.05), .black.opacity(0.22)),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    Text("total").font(Blue.body(12)).foregroundStyle(Blue.sub)
                    Spacer()
                }
                Text("Estimated spend across all sessions (you pay providers directly).")
                    .font(Blue.mono(10)).foregroundStyle(Blue.dim)
            }
        }
        section("CONVERSATION STORAGE") {
            Text("Stored on this Mac — no cloud, no server.")
                .font(Blue.body(12)).foregroundStyle(Blue.sub)
            Text(store.conversationFileDisplayPath)
                .font(Blue.mono(10)).foregroundStyle(Blue.ink)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Button { store.revealConversationFolder() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("REVEAL IN FINDER").font(Blue.mono(10, .bold)).tracking(1)
                }
                .foregroundStyle(Blue.ink).padding(.horizontal, 14).padding(.vertical, 9).background(Blue.glassBright, in: RoundedRectangle(cornerRadius: 10, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    /// EXPORT / IMPORT button in the COUNCILS section.
    private func councilButton(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(Blue.mono(10, .bold)).tracking(1)
                .foregroundStyle(Blue.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(filled ? Blue.glassBright : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Blue.mono(10, .bold)).tracking(2).foregroundStyle(Blue.sub)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // Neutral card (NO material — material sampled the warm desktop behind the sheet and
        // turned these cards brown). A flat adaptive lift keeps them clean in both modes.
        .background(Color.adaptive(.black.opacity(0.045), .white.opacity(0.05)),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
    }

    private func seatBinding(_ seat: Seat) -> Binding<String> {
        Binding(
            get: { store.seats.first { $0.id == seat.id }?.systemPrompt ?? "" },
            set: { store.setSeatPrompt($0, seatID: seat.id) }
        )
    }

    /// One row of the devil's-advocate picker (id -1 = none).
    @ViewBuilder private func advocateRow(id: Int, label: String) -> some View {
        Button { store.devilsAdvocateSeatID = id } label: {
            HStack {
                Text(label).font(Blue.mono(12)).foregroundStyle(Blue.ink)
                Spacer()
                if store.devilsAdvocateSeatID == id {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Blue.ink)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(store.devilsAdvocateSeatID == id ? Blue.glassBright : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Temperature slider + max-tokens field for one seat. nil = AUTO (provider default).
    @ViewBuilder private func samplingControls(for seat: Seat) -> some View {
        let live = store.seats.first { $0.id == seat.id }
        let temp = live?.temperature
        let tempBinding = Binding<Double>(
            get: { temp ?? 1.0 },
            set: { store.setTemperature($0, seatID: seat.id) }
        )
        let maxBinding = Binding<String>(
            get: { live?.maxTokens.map(String.init) ?? "" },
            set: { store.setMaxTokens(Int($0.filter(\.isNumber)), seatID: seat.id) }
        )
        VStack(alignment: .leading, spacing: 7) {
            Text((seat.provider?.panelName ?? "Seat \(seat.id + 1)").uppercased())
                .font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.ink)

            HStack(spacing: 10) {
                Text("TEMP").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    .frame(width: 56, alignment: .leading)
                Slider(value: tempBinding, in: 0...2, step: 0.1).tint(Blue.ink)
                Text(temp == nil ? "AUTO" : String(format: "%.1f", temp ?? 1.0))
                    .font(Blue.mono(10)).foregroundStyle(temp == nil ? Blue.dim : Blue.ink)
                    .frame(width: 40, alignment: .trailing)
                Button { store.setTemperature(nil, seatID: seat.id) } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Blue.sub)
                }
                .buttonStyle(.plain).help("Reset to model default")
                .accessibilityLabel("Reset temperature to default")
            }

            HStack(spacing: 10) {
                Text("MAX TOK").font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    .frame(width: 56, alignment: .leading)
                PlainTextField(text: maxBinding, placeholder: "auto", fontSize: 11,
                               filter: { String($0.filter(\.isNumber).prefix(6)) })
                    .frame(height: 16)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func promptEditor(_ text: Binding<String>, placeholder: String,
                                           label: String? = nil, tall: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let label { Text(label).font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.ink) }
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder).font(Blue.body(12)).foregroundStyle(Blue.dim)
                        .padding(.horizontal, 9).padding(.vertical, 10).allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(Blue.body(12)).foregroundStyle(Blue.ink)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .frame(height: tall ? 96 : 60)
            }
            .background(Color.adaptive(.black.opacity(0.05), .black.opacity(0.22)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
        }
    }
}

private struct SettingsAlerts: ViewModifier {
    let store: CouncilStore
    @Binding var pendingImport: CouncilConfig?
    @Binding var pendingPreset: CouncilConfig?
    func body(content: Content) -> some View {
        content
        .alert("Load this council?",
               isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
               presenting: pendingImport) { config in
            Button("Load") { store.applyConfig(config); pendingImport = nil }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { config in
            Text("“\(config.name)” will replace your current seats, personas, and sampling. Your API keys stay untouched.")
        }
        .alert("Load preset?",
               isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }),
               presenting: pendingPreset) { preset in
            Button("Load") { store.applyConfig(preset); pendingPreset = nil }
            Button("Cancel", role: .cancel) { pendingPreset = nil }
        } message: { preset in
            Text("“\(preset.name)” will replace your current seats and personas. Keys for any models you've already set up are reused.")
        }
    }
}

/// One row in the Settings left rail. Glass pill shows when selected OR hovered.
private struct SettingsTabRow: View {
    let tab: SettingsSheet.Tab
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon).font(.system(size: 13)).frame(width: 18)
                Text(tab.rawValue).font(Blue.mono(11, .bold)).tracking(0.5)
                Spacer()
            }
            .foregroundStyle(Blue.ink)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Blue.glassBright))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Blue.glassStroke, lineWidth: 1))
                    .opacity(selected ? 1 : (hovered ? 0.6 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isOver in withAnimation(.easeOut(duration: 0.16)) { hovered = isOver } }
    }
}

/// One appearance choice. The glow follows the cursor on hover (via `cursorGlow`); when the
/// option is selected and not hovered, the glow rests at the top as a steady indicator.
private struct AppearanceOption: View {
    let label: String
    let value: String
    let icon: String
    @Binding var appearance: String
    @State private var hovered = false

    var body: some View {
        let on = appearance == value
        let lit = on || hovered
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) { appearance = value }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 22, weight: lit ? .bold : .light))
                Text(label).font(Blue.mono(13, .bold)).tracking(3)
            }
            .foregroundStyle(lit ? Blue.ink : Blue.dim)
            .shadow(color: lit ? Blue.ink.opacity(0.4) : .clear, radius: lit ? 12 : 0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .contentShape(Rectangle())
            .cursorGlow(selected: on)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.2), value: hovered)
    }
}

/// Box that fills up (loading / linking) instead of a spinner.
private struct FillBar: View {
    let once: Bool
    @State private var p: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().stroke(Blue.ink, lineWidth: 2)
                Rectangle().fill(Blue.ink.opacity(0.85)).frame(width: g.size.width * p)
            }
        }
        .frame(height: 22)
        .onAppear {
            if once { withAnimation(.easeInOut(duration: 1.1)) { p = 1 } }
            else { withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { p = 1 } }
        }
    }
}

/// A blinking block caret shown at the tail of a streaming answer — terminal feel.
/// Lower-right triangle — used to paint half of a two-color swatch (the other half shows underneath).
private struct DiagonalSplit: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Diagonal slash — marks the "None" swatch as "no tint / default".
private struct Slash: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.22, y: r.maxY - r.height * 0.22))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.22, y: r.minY + r.height * 0.22))
        return p
    }
}

/// One background-tint swatch in the color rail. Grows on hover (so it reads as selectable) and
/// wears a ring when active. None = slashed outline; one color = solid; two colors = a split disc
/// (half/half) so it's obvious it's a mix.
private struct ColorSwatch: View {
    let index: Int
    var dot: CGFloat = 18
    var cell: CGFloat = 30
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    @ViewBuilder private var fill: some View {
        let colors = Blue.bgTints[index].colors
        if colors.isEmpty {
            Circle().fill(Color.clear).overlay(Slash().stroke(Blue.dim, lineWidth: 1.5))
        } else if colors.count == 1 {
            Circle().fill(colors[0])
        } else {
            ZStack {
                Rectangle().fill(colors[0])
                DiagonalSplit().fill(colors[1])
            }
            .clipShape(Circle())
        }
    }

    var body: some View {
        Button(action: action) {
            fill
                .frame(width: dot, height: dot)
                .overlay(Circle().strokeBorder(selected ? Blue.ink : Blue.glassStroke,
                                               lineWidth: selected ? 2 : 1))
                .scaleEffect(hovered ? 1.35 : (selected ? 1.1 : 1.0))
                .frame(maxWidth: .infinity)
                .frame(height: cell)                 // full-cell hit area — easy to click
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Blue.bgTints[index].name)
        .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { hovered = h } }
    }
}

/// Ambient "three advisors" motif — three orbs slowly orbiting while breathing in and out
/// (converge → diverge), embodying the council. Pure decoration; drives the home hero's life.
private struct AdvisorOrbs: View {
    /// Animate ONLY while the hero is hovered. A continuous TimelineView never lets the app idle,
    /// which made everything (especially scrolling) janky — so the orbs rest static and come alive
    /// when you actually look at them.
    var animate: Bool
    var body: some View {
        Group {
            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    orbs(at: ctx.date.timeIntervalSinceReferenceDate)
                }
            } else {
                orbs(at: 0)   // static resting pose
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func orbs(at t: Double) -> some View {
        let r = 13.0 + sin(t * 0.7) * 9.0          // breathe: converge ↔ diverge
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let a = Double(i) / 3.0 * 2.0 * .pi + t * 0.45   // slow rotation
                Circle()
                    .fill(Blue.ink.opacity(0.9 - Double(i) * 0.14))
                    .frame(width: 13, height: 13)
                    .offset(x: CGFloat(cos(a) * r), y: CGFloat(sin(a) * r))
            }
        }
        .frame(width: 76, height: 76)
    }
}

/// The home hero — the living top of the dashboard. The ambient orbs + a rotating example directive
/// (click to start it) + a rotating ethos line. Gives the otherwise-static dashboard a pulse.
private struct HomeHero: View {
    var onPick: (String) -> Void
    @State private var exIndex = 0
    @State private var ethIndex = 0
    @State private var heroHover = false   // orbs animate only while the hero is hovered

    private let examples = [
        "Should I take the job offer or keep looking?",
        "How should I prioritize my week?",
        "What am I missing in this plan?",
        "Is now a good time to make this purchase, or should I wait?",
        "Should I learn a new skill or go deeper on one I have?",
        "Rewrite this paragraph to be sharper and shorter.",
        "What are the trade-offs of renting versus buying?",
        "How do I give difficult feedback without burning the bridge?",
        "Should I focus on one project or keep several going?",
        "What would make this idea stronger?",
        "How do I structure this decision I'm stuck on?",
        "What questions should I be asking that I'm not?",
        "Is it better to specialize or stay a generalist?",
        "How can I make this message clearer and more persuasive?",
        "What are the strongest arguments against my current plan?",
        "Should I automate this or just do it manually for now?",
        "How do I weigh a stable option against a riskier one?",
        "What's a reasonable way to split shared costs fairly?",
        "How should I spend the first 90 days in a new role?",
        "Is this goal realistic for the time I have?",
        "What are the second-order effects of this choice?",
        "How do I say no to this without damaging the relationship?",
        "Should I ship the simple version now or wait for the full one?",
        "What's the best way to learn this topic from scratch?",
        "How do I tell if this is worth my time?",
        "What would I regret not trying a year from now?",
        "How should I prepare for this conversation?",
        "Is this feedback worth acting on, or should I let it go?",
        "What's a fair price to ask for this?",
        "How do I break this big task into manageable steps?",
        "Should I delegate this or keep it myself?",
        "What assumptions am I making that might be wrong?",
        "How do I balance speed and quality here?",
        "What's the simplest version of this that still works?",
        "How do I decide between two good options?",
        "What's the risk I'm underestimating?",
        "How can I make this routine easier to stick to?",
        "Should I keep investing in this or cut my losses?",
        "How do I make a strong first impression here?",
        "What would an outsider notice about this right away?",
        "How do I phrase this so it lands well?",
        "Is this the right problem to be solving?",
        "How should I think about this trade-off?",
        "What's a good way to test this before committing?",
        "How do I stay focused when everything feels urgent?",
        "What would make this plan more resilient?",
        "Should I optimize this now or leave it for later?",
        "How do I get unstuck on this?",
        "What's the honest case for and against this?",
        "How do I know when this is good enough?",
    ]
    private let ethos = [
        "Disagreement is the signal.",
        "Many minds answer — you decide.",
        "Blind peer review keeps them honest.",
        "One question, several lenses.",
        "The council never picks a winner for you.",
    ]

    var body: some View {
        HStack(spacing: 18) {
            AdvisorOrbs(animate: heroHover).frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 7) {
                Text("COUNCIL").font(Blue.mono(17, .bold)).tracking(6).foregroundStyle(Blue.ink)
                Button { onPick(examples[exIndex]) } label: {
                    HStack(spacing: 9) {
                        Text("“\(examples[exIndex])”")
                            .font(Blue.body(14)).foregroundStyle(Blue.sub)
                            .lineLimit(1).truncationMode(.tail)
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Blue.sub)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(exIndex)
                .transition(.opacity)
                .help("Start a directive with this question")
                Text(ethos[ethIndex])
                    .font(Blue.mono(10)).tracking(1).foregroundStyle(Blue.dim)
                    .id(100 + ethIndex)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(corner: 20)
        .onHover { h in heroHover = h }   // bring the orbs to life only while hovering the hero
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.easeInOut(duration: 0.5)) {
                    exIndex = (exIndex + 1) % examples.count
                    ethIndex = (ethIndex + 1) % ethos.count
                }
            }
        }
    }
}

/// Insertion transition: focuses in out of a blur while scaling up — used for the onboarding card.
private struct RevealBlur: ViewModifier {
    let p: Double   // 0 = hidden, 1 = shown
    func body(content: Content) -> some View {
        content
            .blur(radius: (1 - p) * 16)
            .scaleEffect(0.90 + p * 0.10)
            .offset(y: (1 - p) * 18)
            .opacity(p)
    }
}
private extension AnyTransition {
    static var revealBlur: AnyTransition { .modifier(active: RevealBlur(p: 0), identity: RevealBlur(p: 1)) }
}

/// The CONTINUE button. Not blue — on hover it simply fills solid black, label flips to white.
private struct OnboardingEnterButton: View {
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("CONTINUE")
                .font(Blue.mono(11, .bold)).tracking(3)
                .foregroundStyle(hovered ? .white : Blue.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hovered ? Color.black : Blue.glassBright)
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Blue.glassStroke))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovered = h } }
    }
}

/// First-run onboarding — shown once (gated by @AppStorage "council.didOnboard"). Two beats:
/// (1) just the COUNCIL wordmark fades up over a frosted backdrop; (2) tapping anywhere reveals
/// the full explainer card. Lowers BYO-key friction ("one key is enough"). No canvas clutter.
private struct OnboardingCard: View {
    var dismiss: () -> Void
    @State private var appeared = false   // initial frost + wordmark fade
    @State private var revealed = false   // false = wordmark only, true = full card

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("·").font(Blue.mono(12, .bold)).foregroundStyle(Blue.ink)
            Text(text).font(Blue.body(12)).foregroundStyle(Blue.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        ZStack {
            // Frosted, dimmed backdrop — the whole app blurs behind. Tap to advance / dismiss.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .opacity(appeared ? 1 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if revealed { dismiss() }
                    else { withAnimation(.spring(response: 0.9, dampingFraction: 0.84)) { revealed = true } }
                }

            if !revealed {
                // BEAT 1 — just the wordmark + a quiet hint.
                VStack(spacing: 16) {
                    Text("COUNCIL")
                        .font(Blue.mono(34, .bold)).tracking(12).foregroundStyle(Blue.ink)
                    Text("tap anywhere to begin")
                        .font(Blue.mono(10)).tracking(3).foregroundStyle(Blue.dim)
                }
                .scaleEffect(appeared ? 1 : 0.94)
                .blur(radius: appeared ? 0 : 14)
                .opacity(appeared ? 1 : 0)
                .transition(.opacity.combined(with: .scale(scale: 1.08)))
            } else {
                // BEAT 2 — the full explainer card.
                VStack(alignment: .leading, spacing: 0) {
                    Text("COUNCIL").font(Blue.mono(13, .bold)).tracking(5).foregroundStyle(Blue.ink)
                    Text("Parallel answers. Honest disagreement. Your call.")
                        .font(Blue.body(13)).foregroundStyle(Blue.sub)
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 11) {
                        bullet("Ask once — your advisors answer in parallel, then critique each other.")
                        bullet("Bring your own API keys. They stay in your Mac's Keychain — never sent anywhere but the model.")
                        bullet("100% local. No account, no server, no telemetry.")
                    }
                    .padding(.top, 20)

                    Text("One key is enough to begin — pick a model in any panel to start.")
                        .font(Blue.mono(11)).foregroundStyle(Blue.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)

                    OnboardingEnterButton(action: dismiss)
                        .padding(.top, 22)
                }
                .padding(28)
                .frame(width: 420, alignment: .leading)
                .glassPanel(corner: 24)
                .transition(.revealBlur)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { appeared = true }
        }
        // Esc dismisses (from either beat).
        .background {
            Button("", action: dismiss).keyboardShortcut(.escape, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
        }
    }
}

private struct StreamingCaret: View {
    @State private var on = true
    var body: some View {
        Rectangle().fill(Blue.ink)
            .frame(width: 7, height: 14)
            .opacity(on ? 1 : 0.04)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = false }
            }
            .accessibilityHidden(true)
    }
}

/// A clean, screenshot-worthy card used to export a divergence/synthesis as a shareable image.
/// Monochrome, current-theme, with a small "made with Council" watermark (toggleable).
private struct ShareCard: View {
    let title: String
    let via: String?
    let question: String
    let markdown: String
    let watermark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("COUNCIL").font(Blue.serif(26)).foregroundStyle(Blue.ink).tracking(-0.5)
                Spacer()
                Text(via != nil ? "\(title) · VIA \(via!.uppercased())" : title)
                    .font(Blue.mono(10, .bold)).tracking(2).foregroundStyle(Blue.sub)
            }
            if !question.isEmpty {
                Text(question).font(Blue.body(15)).foregroundStyle(Blue.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Blue.glassStroke).frame(height: 1)
            MarkdownView(text: markdown, baseSize: 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            if watermark {
                HStack {
                    Spacer()
                    Text("made with Council").font(Blue.mono(9)).foregroundStyle(Blue.dim)
                }
                .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(width: 900, alignment: .leading)
        .background(Blue.paper)
    }
}

private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

#Preview {
    ContentView(store: CouncilStore())
}
