//
//  ContentView.swift
//  Council
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

/// "Architectural blueprint / brutalist" palette — light by default, with a matching
/// dark (cyberpunk terminal) variant. Every color flips with the chosen appearance.
enum Blue {
    static let bg    = Color.adaptive(Color(red: 0.976, green: 0.976, blue: 0.976), Color(red: 0.05,  green: 0.05,  blue: 0.055)) // #f9f9f9 / near-black
    static let paper = Color.adaptive(.white,                                       Color(red: 0.105, green: 0.105, blue: 0.115)) // panel surface
    static let ink   = Color.adaptive(.black,                                       Color(red: 0.95,  green: 0.95,  blue: 0.96))  // text + borders
    static let grid  = Color.adaptive(Color(red: 0.94,  green: 0.94,  blue: 0.94),  Color(red: 0.16,  green: 0.16,  blue: 0.17))  // grid lines
    static let sub   = Color.adaptive(Color(red: 0.37,  green: 0.37,  blue: 0.37),  Color(red: 0.62,  green: 0.62,  blue: 0.64))  // secondary text
    static let dim   = Color.adaptive(Color(red: 0.78,  green: 0.78,  blue: 0.78),  Color(red: 0.40,  green: 0.40,  blue: 0.42))  // placeholder / disabled
    static let red   = Color.adaptive(Color(red: 0.73,  green: 0.10,  blue: 0.10),  Color(red: 1.0,   green: 0.42,  blue: 0.42))  // error
    static func serif(_ s: CGFloat, _ w: Font.Weight = .bold) -> Font { .system(size: s, weight: w, design: .serif) }
    static func mono(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .monospaced) }
    static func body(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w) }
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

    /// Project name (max 5 chars). Persisted — non-sensitive, so UserDefaults is fine.
    @AppStorage("council.projectName") private var projectName = ""
    @State private var draftName = ""

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

    /// Which canvas the user is looking at: the 3-panel round, or a full-width deliberation artifact.
    enum CanvasMode { case panels, divergence, synthesis }
    @State private var canvasMode: CanvasMode = .panels

    /// History list state.
    @State private var historyQuery = ""
    @State private var renamingSession: UUID?
    @State private var renameText = ""

    private var scheme: ColorScheme { appearance == "dark" ? .dark : .light }

    init(store: CouncilStore) { self.store = store }

    var body: some View {
        ZStack {
            mainUI
            if projectName.isEmpty {
                onboardingOverlay.transition(.opacity)
            }
        }
        // Fill the whole window so content can't size to its *ideal* width and get re-centered
        // (which is what shifted the view when NEW DIRECTIVE emptied the panels).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(scheme)
        .background { if !projectName.isEmpty { shortcutButtons } }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(store: store, appearance: $appearance, projectName: $projectName) { showSettings = false }
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
            Button("") { if !isBusy { store.newSession(); canvasMode = .panels } }
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
        HStack(spacing: 0) {
            if sidebarOpen {
                sidebar.transition(.move(edge: .leading).combined(with: .opacity))
            }
            mainCanvas
                .overlay(alignment: .leading) { sidebarHandle }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gridBackground)
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
                .frame(width: 22, height: 46)
                .background(Blue.paper)
                .overlay(Rectangle().stroke(Blue.ink, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Toggle sidebar")
        .accessibilityLabel(sidebarOpen ? "Collapse sidebar" : "Expand sidebar")
        .offset(x: sidebarOpen ? -11 : 0)
    }

    // MARK: First-launch onboarding (project name, ≤ 5 chars)

    private var onboardingOverlay: some View {
        ZStack {
            gridBackground
            HStack(spacing: 0) {
                // Left: name entry
                VStack(alignment: .leading, spacing: 18) {
                    Text("COUNCIL").font(Blue.serif(40)).foregroundStyle(Blue.ink).tracking(-1)
                    Text("NAME YOUR PROJECT").font(Blue.mono(12, .bold)).tracking(2).foregroundStyle(Blue.sub)

                    HStack(spacing: 2) {
                        Text("PROJECT_").font(Blue.mono(22, .bold)).foregroundStyle(Blue.ink)
                        PlainTextField(text: $draftName, placeholder: "XXXXX",
                                       fontSize: 22, weight: .bold,
                                       filter: { String($0.replacingOccurrences(of: " ", with: "").prefix(5)) },
                                       onSubmit: commitName)
                            .frame(width: 150, height: 30)
                    }
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Blue.ink).frame(height: 2) }

                    Text("MAX 5 CHARACTERS").font(Blue.mono(9)).foregroundStyle(Blue.dim).tracking(1)

                    Button(action: commitName) {
                        Text("INITIALIZE").font(Blue.mono(12, .bold)).tracking(1)
                            .foregroundStyle(Blue.paper)
                            .padding(.horizontal, 34).padding(.vertical, 14)
                            .background(nameReady ? Blue.ink : Blue.dim)
                    }
                    .buttonStyle(.plain)
                    .disabled(!nameReady)
                    .padding(.top, 6)
                }
                .padding(44)
                .frame(width: 400, alignment: .leading)

                Rectangle().fill(Blue.ink).frame(width: 2)

                // Right: where the conversation gets saved (no server)
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "folder").font(.system(size: 30)).foregroundStyle(Blue.ink)
                    Text("CONVERSATION STORAGE").font(Blue.mono(11, .bold)).tracking(2).foregroundStyle(Blue.sub)
                    Text("Your conversations will be saved to:")
                        .font(Blue.body(12)).foregroundStyle(Blue.sub)
                    Text(onboardingSavePath)
                        .font(Blue.mono(10)).foregroundStyle(Blue.ink)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Text("No server — everything stays on this Mac, under your control.")
                        .font(Blue.body(11)).foregroundStyle(Blue.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(36)
                .frame(width: 320, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Blue.paper)
            .overlay(Rectangle().stroke(Blue.ink, lineWidth: 3))
        }
    }

    private var onboardingSavePath: String {
        store.conversationFolderDisplayPath
    }

    private var nameReady: Bool { !draftName.trimmingCharacters(in: .whitespaces).isEmpty }

    private func commitName() {
        let n = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) { projectName = String(n.prefix(5)) }
    }

    // MARK: Background grid

    private var gridBackground: some View {
        Canvas { ctx, size in
            let step: CGFloat = 24
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Blue.grid))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Blue.grid))
                y += step
            }
        }
        .background(Blue.bg)
        .ignoresSafeArea()
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PROJECT_\(projectName.uppercased())")
                    .font(Blue.serif(26)).foregroundStyle(Blue.ink).tracking(-0.5)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            // Extra top room clears the floating traffic lights (hidden title bar).
            .padding(.horizontal, 18).padding(.top, 34).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Blue.ink).frame(height: 2) }

            Button(action: { store.newSession(); canvasMode = .panels }) {
                Text("NEW DIRECTIVE").font(Blue.mono(11, .bold)).tracking(1)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .overlay(Rectangle().stroke(Blue.ink, lineWidth: 2))
            }
            .buttonStyle(.plain).foregroundStyle(Blue.ink).padding(14)
            .disabled(isBusy)
            .opacity(isBusy ? 0.4 : 1)
            .help(isBusy ? "Finish or stop the current generation first" : "Start a new directive")
            .overlay(alignment: .bottom) { Rectangle().fill(Blue.ink).frame(height: 2) }

            sectionLabel("DELIBERATION")

            modeItem("point.3.connected.trianglepath.dotted", "ROUNDTABLE",
                     state: canvasMode == .panels ? .active : .button,
                     action: { canvasMode = .panels })

            modeItem("arrow.2.squarepath", "PEER REVIEW",
                     state: (store.canPeerReview || store.hasPeerReviewForViewedRound) ? .button : .locked,
                     hint: store.hasPeerReviewForViewedRound
                        ? "Show this round's peer review (already generated)"
                        : (store.canPeerReview ? "Models review each other's answers, anonymized"
                                               : "Ask a question first — unlocks once ≥2 models have answered"),
                     action: (store.canPeerReview || store.hasPeerReviewForViewedRound) ? {
                        canvasMode = .panels
                        if !store.hasPeerReviewForViewedRound { runRound { await store.peerReview() } }
                     } : nil)

            modeItem("arrow.triangle.branch", "DIVERGENCE",
                     state: canvasMode == .divergence ? .active : (divergenceAvailable ? .button : .locked),
                     hint: divergenceAvailable ? "Map where advisors agree and diverge"
                                               : "Answer ≥2 advisors first",
                     action: divergenceAvailable ? { canvasMode = .divergence } : nil)

            modeItem("rectangle.3.group", "SYNTHESIS",
                     state: canvasMode == .synthesis ? .active : (synthesisAvailable ? .button : .locked),
                     hint: synthesisAvailable ? "Final answer that preserves the dissent"
                                              : "Answer ≥2 advisors first",
                     action: synthesisAvailable ? { canvasMode = .synthesis } : nil)

            historySection

            Rectangle().fill(Blue.ink).frame(height: 2)
            modeItem("gearshape", "SETTINGS", state: .button) { showSettings = true }
        }
        .frame(width: 256)
        .frame(maxHeight: .infinity)
        .background(Blue.paper)
        .overlay(alignment: .trailing) { Rectangle().fill(Blue.ink).frame(width: 2) }
    }

    private enum ModeState { case active, locked, button }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(Blue.mono(9, .bold)).tracking(2).foregroundStyle(Blue.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 6)
    }

    /// Sidebar = the deliberation pipeline. Only the mode that actually works (ROUND 1,
    /// parallel answers) is active; the rest are honestly shown as locked / not-built-yet.
    /// `.button` is a normal tappable row (e.g. SETTINGS) that runs `action`.
    @ViewBuilder
    private func modeItem(_ icon: String, _ label: String, state: ModeState, hint: String? = nil, action: (() -> Void)? = nil) -> some View {
        let active = state == .active
        let locked = state == .locked
        let row = HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16))
            Text(label).font(Blue.mono(11, .bold)).tracking(1)
            Spacer()
            if locked { Image(systemName: "lock.fill").font(.system(size: 9)) }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .foregroundStyle(active ? Blue.paper : (locked ? Blue.dim : Blue.ink))
        .background(active ? Blue.ink : Color.clear)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Blue.ink).frame(height: 1) }
        .help(hint ?? (locked ? "Not built yet — on the roadmap"
                              : (state == .button ? "Settings" : "Active mode: all models answer in parallel")))

        if let action {
            Button(action: action) { row.contentShape(Rectangle()).cursorGlow() }
                .buttonStyle(.plain)
        } else {
            row.contentShape(Rectangle())
        }
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.searchedSessions(historyQuery)) { session in
                        historyRow(session)
                    }
                    if store.searchedSessions(historyQuery).isEmpty {
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
                store.openSession(s); canvasMode = .panels
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
            Button("Save markdown…") { Exporter.saveMarkdown(store.exportMarkdown(), name: projectName) }
            Button("Save PDF…") { Exporter.savePDF(store.exportMarkdown(), name: projectName) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .bold))
                Text("EXPORT").font(Blue.mono(9, .bold)).tracking(1)
            }
            .foregroundStyle(store.hasSession ? Blue.ink : Blue.dim)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(Rectangle().stroke(Blue.ink.opacity(store.hasSession ? 1 : 0.3), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!store.hasSession)
        .accessibilityLabel("Export conversation")
    }

    private var mainCanvas: some View {
        VStack(spacing: 16) {
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
        .padding(.horizontal, 40).padding(.top, 30).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelGrid: some View {
        // Each panel is locked to exactly one-third of the available width. Without this, a seat
        // whose content has a wide intrinsic size (the model picker) would stretch its column and
        // push the whole window wider — so columns must never size to their content.
        GeometryReader { geo in
            let colWidth = max(0, (geo.size.width - 32) / 3)   // 2 gaps × 16
            HStack(spacing: 16) {
                ForEach(store.seats) { seat in
                    AdvisorPanel(seat: seat,
                                 answer: store.viewedAnswer(seat.id),
                                 peerReview: store.viewedPeerReview(seat.id),
                                 loading: store.isViewingLatest && store.status[seat.id] == .loading,
                                 failedMessage: panelFailure(seat.id),
                                 connected: connected(seat),
                                 canRegenerate: store.isViewingLatest,
                                 isAdversary: store.devilsAdvocateSeatID == seat.id,
                                 onValidateKey: { await store.validateAndSaveKey($0, for: seat) },
                                 onSetModel: { store.setModel($0, seatID: seat.id) },
                                 onPickProvider: { pickProvider($0, for: seat) },
                                 onResetSeat: { store.clearProvider(seatID: seat.id) },
                                 onRegenerate: { runRound { await store.regenerate(seatID: seat.id) } })
                        .frame(width: colWidth)
                        .clipped()
                        .overlay(Rectangle().stroke(Blue.ink, lineWidth: 3))
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
                        .frame(width: 26, height: 24)
                        .overlay(Rectangle().stroke(Blue.ink.opacity(store.canGoPrevRound ? 1 : 0.3), lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!store.canGoPrevRound)
                .accessibilityLabel("Previous round")

                Button { store.nextRound() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(store.canGoNextRound ? Blue.ink : Blue.dim)
                        .frame(width: 26, height: 24)
                        .overlay(Rectangle().stroke(Blue.ink.opacity(store.canGoNextRound ? 1 : 0.3), lineWidth: 1.5))
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
            exportMenu
        }
    }

    /// A quiet outlined chip marking that the viewed round already has this artifact (DIV / SYN).
    private func roundTag(_ s: String) -> some View {
        Text(s).font(Blue.mono(8, .bold)).tracking(1).foregroundStyle(Blue.sub)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(Rectangle().stroke(Blue.ink.opacity(0.3), lineWidth: 1))
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
                        .foregroundStyle(Blue.sub).contentShape(Rectangle())
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
                        .foregroundStyle(Blue.sub).contentShape(Rectangle())
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
                    .overlay(Rectangle().stroke(Blue.ink, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).cursorGlow()
            }
            .padding(20)
            .overlay(alignment: .bottom) { Rectangle().fill(Blue.ink).frame(height: 2) }

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
                            .foregroundStyle(canGenerate ? Blue.paper : Blue.dim)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(canGenerate ? Blue.ink : Blue.dim.opacity(0.4))
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
        .background(Blue.paper)
        .overlay(Rectangle().stroke(Blue.ink, lineWidth: 3))
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
        VStack(alignment: .leading, spacing: 12) {
            if let img = pickedImage {
                HStack(spacing: 10) {
                    Button { showImagePreview = true } label: {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 46).clipped()
                            .overlay(Rectangle().stroke(Blue.ink, lineWidth: 2))
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

            HStack(spacing: 16) {
                Button(action: pickImage) {
                    Image(systemName: "photo").font(.system(size: 13)).foregroundStyle(Blue.ink)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach image")
                .accessibilityLabel("Attach image")
                ComposerTextView(text: $query, placeholder: "Enter..",
                                 onSubmit: ask, onPasteImage: { pickedImage = $0 })
                    .frame(maxWidth: .infinity)
                    .frame(height: composerHeight)
                Button(action: isBusy ? stop : ask) {
                    Text(isBusy ? "STOP" : "EXECUTE").font(Blue.mono(11, .bold)).tracking(1)
                        .foregroundStyle((isBusy || canAsk) ? Blue.paper : Blue.dim)
                        .padding(.horizontal, 18).padding(.vertical, 5)
                        .background(isBusy ? Blue.red : (canAsk ? Blue.ink : Blue.dim.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .disabled(!isBusy && !canAsk)
            }
        }
        .padding(7)
        .background(Blue.paper)
        .overlay(Rectangle().stroke(Blue.ink, lineWidth: isDropTargeted ? 4 : 3))
        .overlay(alignment: .topTrailing) {
            if store.sessionInputTokens + store.sessionOutputTokens > 0 {
                Text("Σ \(tokenString) · ~\(costString)")
                    .font(Blue.mono(9)).foregroundStyle(Blue.sub)
                    .padding(.horizontal, 6).background(Blue.paper)
                    .offset(x: -16, y: -7)
                    .help("Session tokens · estimated cost (you pay providers directly)")
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleImageDrop(providers)
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
                        .overlay(Rectangle().stroke(Blue.ink, lineWidth: 2))
                        .contentShape(Rectangle())
                        .cursorGlow()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close image preview")
            }
            .padding(20)
            Rectangle().fill(Blue.ink).frame(height: 2)

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

// MARK: - Advisor panel

private struct AdvisorPanel: View {
    let seat: Seat
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

            DashLine().stroke(Blue.ink, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1).padding(.vertical, hasConversation ? 8 : 12)

            statusLine
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Blue.paper)
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
                Text((seat.provider?.panelName ?? "—").uppercased())
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change model — back to picker")
                .accessibilityLabel("Change model")
            }
        }
        .padding(.bottom, hasConversation ? 8 : 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Blue.ink).frame(height: hasConversation ? 1 : 2) }
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

    private var statusLine: some View {
        HStack(spacing: 8) {
            Rectangle().fill(failed ? Blue.red : Blue.ink)
                .frame(width: hasConversation ? 6 : 8, height: hasConversation ? 6 : 8)
            Text("STATUS: \(statusText)")
                .font(Blue.mono(hasConversation ? 9 : 11, .bold))
                .foregroundStyle(failed ? Blue.red : Blue.ink)
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
                        .background(m == seat.model ? Blue.ink.opacity(0.08) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx < options.count - 1 {
                        Rectangle().fill(Blue.ink.opacity(0.12)).frame(height: 1)
                    }
                }
            }
            .overlay(Rectangle().stroke(Blue.ink, lineWidth: 2))

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
                .overlay(Rectangle().stroke(Blue.ink, lineWidth: 2))
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
        .background(Blue.paper)
        .overlay(Rectangle().stroke(open ? Blue.ink : Blue.ink.opacity(0.35), lineWidth: 2))
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
                        Text(note).font(Blue.mono(8)).tracking(0.5).foregroundStyle(Blue.dim)
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
            .background(hovered ? Blue.ink.opacity(0.06) : Color.clear)
            .overlay(Rectangle().stroke(hovered ? Blue.ink : Blue.ink.opacity(0.22),
                                        lineWidth: hovered ? 2 : 1.5))
            .cursorGlow()
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
    @Binding var projectName: String
    var onClose: () -> Void

    /// Local draft so the field can be edited (even transiently empty) without ever pushing an
    /// empty name back to storage — an empty projectName would re-trigger the onboarding overlay.
    @State private var projectDraft = ""
    /// Whether exported images carry the "made with Council" watermark. Default on (growth).
    @AppStorage("council.shareWatermark") private var shareWatermark = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SETTINGS").font(Blue.serif(28)).foregroundStyle(Blue.ink).tracking(-0.5)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Blue.ink)
                        .frame(width: 30, height: 30)
                        .overlay(Rectangle().stroke(Blue.ink, lineWidth: 2))
                        .contentShape(Rectangle())
                        .cursorGlow()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close settings")
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
            Rectangle().fill(Blue.ink).frame(height: 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    section("PROJECT") {
                        HStack(spacing: 2) {
                            Text("PROJECT_").font(Blue.mono(15, .bold)).foregroundStyle(Blue.ink)
                            PlainTextField(text: $projectDraft, placeholder: "XXXXX",
                                           fontSize: 15, weight: .bold,
                                           filter: { String($0.replacingOccurrences(of: " ", with: "").prefix(5)) })
                                .frame(width: 110, height: 22)
                                .overlay(alignment: .bottom) { Rectangle().fill(Blue.ink).frame(height: 1.5) }
                        }
                        Text("Shown in the sidebar and used as the export filename. Max 5 characters.")
                            .font(Blue.body(11)).foregroundStyle(Blue.sub)
                    }

                    section("APPEARANCE") {
                        HStack(spacing: 0) {
                            AppearanceOption(label: "LIGHT", value: "light", icon: "sun.max", appearance: $appearance)
                            AppearanceOption(label: "DARK", value: "dark", icon: "moon", appearance: $appearance)
                        }
                    }

                    section("SYSTEM PROMPT — ALL MODELS") {
                        promptEditor($store.sharedSystemPrompt, placeholder: "Shared instruction…", tall: true)
                        Button { store.sharedSystemPrompt = CouncilStore.defaultSystemPrompt } label: {
                            Text("RESET TO DEFAULT").font(Blue.mono(9, .bold)).tracking(1).foregroundStyle(Blue.sub)
                        }
                        .buttonStyle(.plain)
                    }

                    section("PER-MODEL (OPTIONAL)") {
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
                                    .background(store.synthesizerSeatID == seat.id ? Blue.ink.opacity(0.08) : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if idx < store.seats.count - 1 {
                                    Rectangle().fill(Blue.ink.opacity(0.12)).frame(height: 1)
                                }
                            }
                        }
                        .overlay(Rectangle().stroke(Blue.ink, lineWidth: 2))
                    }

                    section("DEVIL'S ADVOCATE") {
                        Text("One advisor steelmans the emerging consensus, then attacks it — mandated dissent in peer review. Off by default.")
                            .font(Blue.body(11)).foregroundStyle(Blue.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 0) {
                            advocateRow(id: -1, label: "None")
                            Rectangle().fill(Blue.ink.opacity(0.12)).frame(height: 1)
                            ForEach(Array(store.seats.enumerated()), id: \.element.id) { idx, seat in
                                advocateRow(id: seat.id, label: seat.provider?.panelName ?? "Seat \(seat.id + 1)")
                                if idx < store.seats.count - 1 {
                                    Rectangle().fill(Blue.ink.opacity(0.12)).frame(height: 1)
                                }
                            }
                        }
                        .overlay(Rectangle().stroke(Blue.ink, lineWidth: 2))
                    }

                    section("SHARING") {
                        Toggle(isOn: $shareWatermark) {
                            Text("Show “made with Council” on exported images")
                                .font(Blue.body(12)).foregroundStyle(Blue.ink)
                        }
                        .toggleStyle(.switch).tint(Blue.ink)
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
                            .foregroundStyle(Blue.paper).padding(.horizontal, 14).padding(.vertical, 9).background(Blue.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(28)
            }
        }
        .frame(width: 560, height: 660)
        .background(Blue.bg)
        .onAppear { projectDraft = projectName }
        .onChange(of: projectDraft) { _, new in
            let v = String(new.prefix(5))
            if !v.isEmpty { projectName = v }   // never write empty — that would re-open onboarding
        }
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Blue.mono(10, .bold)).tracking(2).foregroundStyle(Blue.sub)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .background(store.devilsAdvocateSeatID == id ? Blue.ink.opacity(0.08) : Color.clear)
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
                    .overlay(Rectangle().stroke(Blue.ink.opacity(0.4), lineWidth: 1.5))
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
            .background(Blue.paper)
            .overlay(Rectangle().stroke(Blue.ink, lineWidth: 1.5))
        }
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
            Rectangle().fill(Blue.ink).frame(height: 2)
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
