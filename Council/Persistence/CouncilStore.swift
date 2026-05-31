import Foundation
import Observation
import AppKit

/// Per-seat live state (applies to the round currently being generated).
enum SeatStatus: Equatable { case idle, loading, failed(String) }

/// Central app state. A session is a list of `Round`s; each round keeps its own answers,
/// peer reviews, divergence and synthesis. The user navigates rounds; nothing is wiped.
@MainActor
@Observable
final class CouncilStore {
    var seats: [Seat]
    var status: [Int: SeatStatus] = [:]
    /// All rounds in the current session, oldest → newest.
    var rounds: [Round] = []
    /// Which round the UI is showing (analyses + answers are read from this round).
    var viewingRound = 0
    /// True while a divergence/synthesis round is running.
    var deliberationBusy = false
    /// Transient (NEVER persisted) error from the last divergence / synthesis attempt. We never
    /// write an error string into a round's content — a failed network call must not become
    /// permanent "analysis" saved to disk. Shown briefly in the canvas, cleared on retry/nav.
    var divergenceError: String?
    var synthesisError: String?
    /// Bumped whenever a key is saved, so views re-evaluate `hasKey`.
    var keyRevision = 0

    /// Full per-seat conversation (user/assistant turns, no system). Replayed on Round 1 calls
    /// so each model has its own prior context across rounds.
    private var history: [Int: [ChatMessage]] = [:]

    /// Shared Round-1 system prompt — the "advisor" instruction, user-editable. A seat can
    /// override it (see `Seat.systemPrompt`). Persisted in UserDefaults (non-sensitive).
    var sharedSystemPrompt: String = CouncilStore.defaultSystemPrompt {
        didSet { UserDefaults.standard.set(sharedSystemPrompt, forKey: Self.promptKey) }
    }

    /// Which seat generates divergence + synthesis (and so spends that provider's credit). Persisted.
    var synthesizerSeatID: Int = 0 {
        didSet { UserDefaults.standard.set(synthesizerSeatID, forKey: Self.synthKey) }
    }

    /// Which seat (if any) plays devil's advocate — in peer review it steelmans then attacks the
    /// emerging consensus instead of looking for agreement. -1 = none. Persisted.
    var devilsAdvocateSeatID: Int = -1 {
        didSet { UserDefaults.standard.set(devilsAdvocateSeatID, forKey: Self.devilKey) }
    }

    private let seatsKey = "council.seats.v5"
    private static let promptKey = "council.systemPrompt"
    private static let synthKey = "council.synthesizerSeat"
    private static let devilKey = "council.devilsAdvocate"
    static let defaultSystemPrompt =
        "You are one of three AI advisors on a council. Answer the user's question directly, clearly, and concisely, in your own voice."

    private static let peerReviewPrompt = """
    You are one of three AI advisors on a council and you have already given your own answer. \
    Below are the other advisors' answers to the same question, anonymized. Review them critically: \
    state clearly where you AGREE and where you DISAGREE, and why. If one of them changed your mind, \
    say so and refine your view. If you still disagree, hold your ground and explain — do NOT cave to \
    consensus just to agree. Be concise, honest, and in your own voice.
    """

    private static let adversaryReviewPrompt = """
    You are the council's Devil's Advocate. Your job is NOT to find agreement — it is to stress-test \
    the emerging consensus. First steelman the position the other advisors seem to share: state it in \
    its strongest, fairest form. Then attack it — surface the strongest objections, the overlooked \
    risks, the failure modes, and the best case for the opposite conclusion. Be specific and \
    intellectually honest: if the consensus genuinely survives scrutiny, say exactly what would have \
    to be true for it to be wrong. Do NOT soften your critique just to be agreeable.
    """

    private static let divergencePrompt = """
    You are the council's analyst. You are given the advisors' answers to a question. Map the \
    deliberation in two clearly-headed markdown sections: "## Agreement" (points most or all advisors \
    share) and "## Divergence" (where they disagree — name which advisor holds which view, and why). \
    Be specific and concise. Do NOT pick a winner; just map the landscape honestly.
    """

    private static let synthesisPrompt = """
    You are the council's synthesizer. Given the advisors' answers, produce a \
    final synthesis in markdown with two parts: a clear, decisive recommended answer first; then a \
    section "## Where they diverged" that explicitly preserves the dissent — note where advisors \
    disagreed and why, without flattening it into false consensus. The human decides: give them a \
    clear map, not a command.
    """

    init() {
        if let data = UserDefaults.standard.data(forKey: seatsKey),
           let saved = try? JSONDecoder().decode([Seat].self, from: data), saved.count == 3 {
            seats = saved
        } else {
            // Start unassigned so every seat goes through the same PICK → SELECT MODEL → key flow
            // (a pre-assigned key-required seat would otherwise jump straight to key entry,
            // skipping model selection — confusing for a first run).
            seats = [
                Seat(id: 0, archetype: .sage),
                Seat(id: 1, archetype: .scientist),
                Seat(id: 2, archetype: .strategist)
            ]
        }
        if let savedPrompt = UserDefaults.standard.string(forKey: Self.promptKey), !savedPrompt.isEmpty {
            sharedSystemPrompt = savedPrompt
        }
        if let n = UserDefaults.standard.object(forKey: Self.synthKey) as? Int { synthesizerSeatID = n }
        if let n = UserDefaults.standard.object(forKey: Self.devilKey) as? Int { devilsAdvocateSeatID = n }
        loadSessions()
    }

    func saveSeats() {
        if let data = try? JSONEncoder().encode(seats) {
            UserDefaults.standard.set(data, forKey: seatsKey)
        }
    }

    func setSeatPrompt(_ prompt: String?, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        seats[idx].systemPrompt = (prompt?.isEmpty == false) ? prompt : nil
        saveSeats()
    }

    // MARK: - Keys

    var isConfigured: Bool { seats.allSatisfy(hasKey) }

    func hasKey(_ seat: Seat) -> Bool {
        guard let provider = seat.provider else { return false }   // no model picked yet
        guard provider.requiresAPIKey else { return true }          // e.g. local Ollama
        let key = try? KeychainStore.read(account: provider.keychainAccount)
        return (key?.isEmpty == false)
    }

    func setKey(_ key: String, for provider: LLMProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? KeychainStore.save(trimmed, account: provider.keychainAccount)
        keyRevision += 1
    }

    func clearKey(for provider: LLMProvider) {
        KeychainStore.delete(account: provider.keychainAccount)
        keyRevision += 1
    }

    func validateAndSaveKey(_ key: String, for seat: Seat) async -> String? {
        guard let provider = seat.provider else { return "No model selected." }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Empty key." }
        let client = LLMClientFactory.make(for: provider, model: seat.model)
        do { try await client.validate(apiKey: trimmed) } catch { return error.localizedDescription }
        setKey(trimmed, for: provider)
        return nil
    }

    func setModel(_ model: String, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        seats[idx].model = trimmed.isEmpty ? (seats[idx].provider?.defaultModel ?? "") : trimmed
        saveSeats()
    }

    /// Assign (or change) a seat's provider, resetting the model to that provider's default.
    func setProvider(_ provider: LLMProvider, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        seats[idx].provider = provider
        seats[idx].model = provider.defaultModel
        saveSeats()
        keyRevision += 1
    }

    /// Reset a seat back to unassigned ("PICK YOUR MODEL").
    func clearProvider(seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        seats[idx].provider = nil
        seats[idx].model = ""
        saveSeats()
        keyRevision += 1
    }

    /// True if another seat already uses this provider — drives the duplicate-token warning.
    func providerInUse(_ provider: LLMProvider, excluding seatID: Int) -> Bool {
        seats.contains { $0.id != seatID && $0.provider == provider }
    }

    /// Per-seat sampling override. Passing nil clears it (falls back to provider default).
    func setTemperature(_ value: Double?, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        seats[idx].temperature = value.map { min(max($0, 0), 2) }   // clamp to a sane range
        saveSeats()
    }

    func setMaxTokens(_ value: Int?, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        // Treat 0/negative as "no override"; cap very large values to avoid runaway costs.
        if let v = value, v > 0 { seats[idx].maxTokens = min(v, 64_000) }
        else { seats[idx].maxTokens = nil }
        saveSeats()
    }

    // MARK: - Round navigation + viewed accessors

    var roundCount: Int { rounds.count }
    var isViewingLatest: Bool { viewingRound >= rounds.count - 1 }
    var canGoPrevRound: Bool { viewingRound > 0 }
    var canGoNextRound: Bool { viewingRound < rounds.count - 1 }
    func prevRound() { if canGoPrevRound { viewingRound -= 1; clearDeliberationErrors() } }
    func nextRound() { if canGoNextRound { viewingRound += 1; clearDeliberationErrors() } }

    /// Drop the transient divergence/synthesis errors (they belong to one attempt on one round).
    func clearDeliberationErrors() { divergenceError = nil; synthesisError = nil }

    private var viewedRound: Round? { rounds.indices.contains(viewingRound) ? rounds[viewingRound] : nil }
    var viewedQuestion: String { viewedRound?.question ?? "" }
    func viewedAnswer(_ seatID: Int) -> String? { viewedRound?.answers[seatID] }
    func viewedPeerReview(_ seatID: Int) -> String? { viewedRound?.peerReviews[seatID] }
    /// Read-only views of the current round's cross-model artifacts (used by the UI).
    var divergenceText: String? { viewedRound?.divergence }
    var synthesisText: String? { viewedRound?.synthesis }

    /// Session token + cost totals (sum across rounds) — an estimate.
    var sessionInputTokens: Int { rounds.reduce(0) { $0 + $1.inputTokens } }
    var sessionOutputTokens: Int { rounds.reduce(0) { $0 + $1.outputTokens } }
    var sessionCostUSD: Double { rounds.reduce(0) { $0 + $1.costUSD } }

    private func answeredSeats(in idx: Int) -> [Seat] {
        guard rounds.indices.contains(idx) else { return [] }
        return seats.filter { hasKey($0) && !((rounds[idx].answers[$0.id] ?? "").isEmpty) }
    }
    private var anyLoading: Bool { status.values.contains { $0 == .loading } || deliberationBusy }
    /// True while any advisor or a deliberation round is generating. The UI uses this to lock
    /// session switching so an in-flight write can't land in a session swapped out underneath it.
    var isWorking: Bool { anyLoading }
    /// The chosen synthesizer seat if it has a key; otherwise the first connected seat.
    private var synthesizerSeat: Seat? {
        if let chosen = seats.first(where: { $0.id == synthesizerSeatID }), hasKey(chosen) { return chosen }
        return seats.first { hasKey($0) }
    }
    private func canDeliberate(_ idx: Int) -> Bool { answeredSeats(in: idx).count >= 2 && !anyLoading }

    /// Peer review / divergence / synthesis operate on the round you're viewing.
    var canPeerReview: Bool { canDeliberate(viewingRound) }
    var canSynthesize: Bool { canDeliberate(viewingRound) }
    /// Whether the viewed round already has peer reviews (so clicking PEER REVIEW just shows them).
    var hasPeerReviewForViewedRound: Bool {
        viewedRound?.peerReviews.values.contains { !$0.isEmpty } ?? false
    }
    var synthesizerName: String? { synthesizerSeat?.provider?.panelName }
    var hasSession: Bool { rounds.contains { !$0.answeredSeatIDs.isEmpty } }

    // MARK: - Rounds

    /// Round 1: a NEW round; every connected seat answers in parallel, streaming token-by-token,
    /// each with its own prior context. An optional image rides on the question.
    func ask(_ query: String, image: ImageAttachment? = nil) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil else { return }
        let prompt = trimmed.isEmpty ? "Describe and assess this image." : trimmed

        let keyed = seats.filter { hasKey($0) }
        guard !keyed.isEmpty else { return }
        var round = Round(question: prompt)
        for seat in keyed { round.answers[seat.id] = "" }   // in-progress slots
        rounds.append(round)
        let idx = rounds.count - 1
        viewingRound = idx
        clearDeliberationErrors()
        for seat in keyed { status[seat.id] = .loading }

        await withTaskGroup(of: Void.self) { group in
            for seat in keyed {
                let sys = systemPrompt(for: seat)
                let messages = [ChatMessage.system(sys)] + (history[seat.id] ?? []) + [.user(prompt, image: image)]
                group.addTask { @MainActor in
                    let r = await self.streamCall(seat: seat, messages: messages) { partial in
                        self.setAnswer(idx, seat.id, partial)
                    }
                    self.finishAnswer(roundIndex: idx, seat: seat, question: prompt, result: r)
                }
            }
        }
        saveConversation()
    }

    /// Round 2: each advisor reviews the others' answers (anonymized) for the VIEWED round.
    func peerReview() async {
        let idx = viewingRound
        let answered = answeredSeats(in: idx)
        guard answered.count >= 2, rounds.indices.contains(idx) else { return }
        let pairs = answered.map { (seat: $0, answer: rounds[idx].answers[$0.id] ?? "") }
        for s in answered { status[s.id] = .loading; rounds[idx].peerReviews[s.id] = "" }

        await withTaskGroup(of: Void.self) { group in
            for (seat, myAnswer) in pairs {
                let others = pairs.filter { $0.seat.id != seat.id }
                // Blind the reviewer with anonymous labels (no brand bias), but keep a map back
                // to real names so the READER sees "I disagree with Gemini", not "Advisor B".
                var remap: [String: String] = [:]
                let othersText = others.enumerated().map { i, p -> String in
                    let label = "Advisor \(String(UnicodeScalar(65 + i)!))"
                    remap[label] = p.seat.provider?.panelName ?? "Advisor"
                    return "\(label) said:\n\(p.answer)"
                }.joined(separator: "\n\n")
                let reviewText = """
                Your own answer was:

                \(myAnswer)

                The other advisors answered the same question as follows:

                \(othersText)

                Review their answers: where do you agree, where do you disagree, and would you refine your own answer? Be specific.
                """
                // The devil's advocate gets an adversarial brief instead of the standard reviewer one.
                let reviewSystem = (seat.id == devilsAdvocateSeatID) ? Self.adversaryReviewPrompt : Self.peerReviewPrompt
                let messages = [ChatMessage.system(reviewSystem), .user(reviewText)]
                group.addTask { @MainActor in
                    let r = await self.streamCall(seat: seat, messages: messages) { partial in
                        if self.rounds.indices.contains(idx) {
                            self.rounds[idx].peerReviews[seat.id] = self.deAnonymize(partial, remap)
                        }
                    }
                    guard self.rounds.indices.contains(idx) else { return }
                    if let text = r.text {
                        self.rounds[idx].peerReviews[seat.id] = self.deAnonymize(text, remap)
                        self.status[seat.id] = .idle
                        self.addRoundUsage(idx, seat, r)
                    } else if r.cancelled {
                        self.status[seat.id] = .idle
                    } else {
                        self.rounds[idx].peerReviews[seat.id] = nil
                        self.status[seat.id] = .failed(r.error ?? "Unknown error")
                    }
                }
            }
        }
        saveConversation()
    }

    func runDivergence() async {
        let idx = viewingRound
        guard canDeliberate(idx), let seat = synthesizerSeat, rounds.indices.contains(idx) else { return }
        deliberationBusy = true
        divergenceError = nil
        // Don't wipe an existing divergence up front: on a failed REGEN the prior good text stays,
        // and the stream replaces it from the first token on success.
        let (ctx, remap) = anonymizedContext(idx)
        let user = "Question:\n\(rounds[idx].question)\n\nThe advisors' answers (anonymized):\n\n\(ctx)"
        let r = await streamCall(seat: seat, messages: [.system(Self.divergencePrompt), .user(user)]) { partial in
            if self.rounds.indices.contains(idx) { self.rounds[idx].divergence = self.deAnonymize(partial, remap) }
        }
        if rounds.indices.contains(idx) {
            if let t = r.text, !r.cancelled { rounds[idx].divergence = deAnonymize(t, remap); addRoundUsage(idx, seat, r) }
            else if !r.cancelled { divergenceError = r.error ?? "Failed" }   // transient, never persisted as content
        }
        deliberationBusy = false
        saveConversation()
    }

    func runSynthesis() async {
        let idx = viewingRound
        guard canDeliberate(idx), let seat = synthesizerSeat, rounds.indices.contains(idx) else { return }
        deliberationBusy = true
        synthesisError = nil
        let (ctx, remap) = anonymizedContext(idx)
        let context = "Question:\n\(rounds[idx].question)\n\nThe advisors' answers (anonymized):\n\n\(ctx)"
        let r = await streamCall(seat: seat, messages: [.system(Self.synthesisPrompt), .user(context)]) { partial in
            if self.rounds.indices.contains(idx) { self.rounds[idx].synthesis = self.deAnonymize(partial, remap) }
        }
        if rounds.indices.contains(idx) {
            if let t = r.text, !r.cancelled { rounds[idx].synthesis = deAnonymize(t, remap); addRoundUsage(idx, seat, r) }
            else if !r.cancelled { synthesisError = r.error ?? "Failed" }   // transient, never persisted as content
        }
        deliberationBusy = false
        saveConversation()
    }

    /// Re-run a single advisor's answer in the latest round (only when viewing it).
    func regenerate(seatID: Int) async {
        let idx = rounds.count - 1
        guard idx == viewingRound, rounds.indices.contains(idx), !anyLoading,
              let seat = seats.first(where: { $0.id == seatID }), hasKey(seat) else { return }
        let q = rounds[idx].question
        // Only drop this seat's last exchange from history if it actually succeeded (so a
        // retry-after-failure doesn't wrongly delete a previous round's exchange).
        let hadAnswer = !((rounds[idx].answers[seatID] ?? "").isEmpty)
        if hadAnswer, var h = history[seatID], h.count >= 2 { h.removeLast(2); history[seatID] = h }
        // Changing one answer invalidates every peer review (they all read the old set) and both
        // cross-model artifacts — clear them all so nothing stale survives next to the new answer.
        rounds[idx].peerReviews.removeAll()
        rounds[idx].divergence = nil
        rounds[idx].synthesis = nil
        divergenceError = nil; synthesisError = nil
        rounds[idx].answers[seatID] = ""
        status[seatID] = .loading
        let messages = [ChatMessage.system(systemPrompt(for: seat))] + (history[seatID] ?? []) + [.user(q)]
        let r = await streamCall(seat: seat, messages: messages) { partial in
            self.setAnswer(idx, seatID, partial)
        }
        finishAnswer(roundIndex: idx, seat: seat, question: q, result: r)
        saveConversation()
    }

    func cancelAll() {
        for id in status.keys where status[id] == .loading { status[id] = .idle }
        deliberationBusy = false
    }

    // MARK: - Round helpers

    private func systemPrompt(for seat: Seat) -> String {
        (seat.systemPrompt?.isEmpty == false) ? seat.systemPrompt! : sharedSystemPrompt
    }

    private func setAnswer(_ idx: Int, _ seatID: Int, _ text: String) {
        guard rounds.indices.contains(idx) else { return }
        rounds[idx].answers[seatID] = text
    }

    private func finishAnswer(roundIndex idx: Int, seat: Seat, question: String, result r: StreamResult) {
        guard rounds.indices.contains(idx) else { return }
        let id = seat.id
        if let text = r.text, !r.cancelled {
            // Completed normally → commit the answer and extend this seat's conversation history.
            rounds[idx].answers[id] = text
            history[id, default: []].append(.user(question))
            history[id, default: []].append(.assistant(text))
            status[id] = .idle
            addRoundUsage(idx, seat, r)
        } else if r.cancelled {
            // Stopped mid-stream: keep whatever streamed for the user to read, but do NOT append it
            // to history — feeding a truncated answer into later rounds as if complete corrupts context.
            rounds[idx].answers[id] = r.text   // partial text, or nil if nothing arrived yet
            status[id] = .idle
        } else {
            rounds[idx].answers[id] = nil   // hard failure → drop the empty in-progress slot
            status[id] = .failed(r.error ?? "Unknown error")
        }
    }

    private func addRoundUsage(_ idx: Int, _ seat: Seat, _ r: StreamResult) {
        guard rounds.indices.contains(idx), let provider = seat.provider,
              r.input > 0 || r.output > 0 else { return }
        rounds[idx].inputTokens += r.input
        rounds[idx].outputTokens += r.output
        rounds[idx].costUSD += Double(r.input) / 1_000_000 * provider.pricePer1MInput
                             + Double(r.output) / 1_000_000 * provider.pricePer1MOutput
    }

    /// Build the answers for the synthesizer with ANONYMOUS, shuffled labels (Advisor A/B/C) so it
    /// can't tell which answer is its own and favor it. Returns the context plus a map from each
    /// anonymous label back to the real provider name (used to restore attribution in the output).
    private func anonymizedContext(_ idx: Int) -> (context: String, remap: [String: String]) {
        let answered = answeredSeats(in: idx).shuffled()
        var blocks: [String] = []
        var remap: [String: String] = [:]
        for (i, s) in answered.enumerated() {
            let label = "Advisor \(String(UnicodeScalar(65 + i)!))"   // Advisor A, B, C…
            remap[label] = s.provider?.panelName ?? "Advisor"
            blocks.append("\(label):\n\(rounds[idx].answers[s.id] ?? "")")
        }
        return (blocks.joined(separator: "\n\n"), remap)
    }

    /// Put the real provider names back into a generated artifact, for display.
    private func deAnonymize(_ text: String, _ remap: [String: String]) -> String {
        var out = text
        for (label, name) in remap { out = out.replacingOccurrences(of: label, with: name) }
        return out
    }

    typealias StreamResult = (text: String?, input: Int, output: Int, cancelled: Bool, error: String?)

    /// Stream one model call, feeding the growing text to `onDelta`. Returns final text (nil on
    /// hard failure), token usage, and whether it was cancelled (partial text is kept on cancel).
    private func streamCall(seat: Seat, messages: [ChatMessage],
                            onDelta: @MainActor @escaping (String) -> Void) async -> StreamResult {
        guard let provider = seat.provider else { return (nil, 0, 0, false, "No model selected.") }
        var apiKey = ""
        if provider.requiresAPIKey {
            guard let key = (try? KeychainStore.read(account: provider.keychainAccount)) ?? nil,
                  !key.isEmpty else { return (nil, 0, 0, false, "API key not found.") }
            apiKey = key
        }
        let client = LLMClientFactory.make(for: provider, model: seat.model,
                                           temperature: seat.temperature, maxTokens: seat.maxTokens)
        var full = "", input = 0, output = 0
        do {
            for try await chunk in client.stream(messages: messages, apiKey: apiKey) {
                try Task.checkCancellation()   // Stop → exit → stream terminates → network cancels
                switch chunk {
                case .text(let t):         full += t; onDelta(full)
                case .usage(let i, let o): input = i; output = o
                }
            }
            return (full, input, output, false, nil)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return (full.isEmpty ? nil : full, input, output, true, nil)
            }
            return (nil, input, output, false, error.localizedDescription)
        }
    }

    // MARK: - Export

    func exportMarkdown() -> String {
        var out = "# Council\n\n"
        for (i, round) in rounds.enumerated() where !round.answeredSeatIDs.isEmpty {
            out += "## Round \(i + 1) — \(round.question)\n\n"
            for seat in seats where !((round.answers[seat.id] ?? "").isEmpty) {
                out += "### \(seat.provider?.panelName ?? "Advisor") — `\(seat.model)`\n\n\(round.answers[seat.id] ?? "")\n\n"
            }
            let reviews = seats.filter { !((round.peerReviews[$0.id] ?? "").isEmpty) }
            if !reviews.isEmpty {
                out += "#### Peer Review\n\n"
                for seat in reviews { out += "**\(seat.provider?.panelName ?? "Advisor"):** \(round.peerReviews[seat.id] ?? "")\n\n" }
            }
            if let d = round.divergence { out += "#### Divergence\n\n\(d)\n\n" }
            if let s = round.synthesis { out += "#### Synthesis\n\n\(s)\n\n" }
        }
        return out
    }

    // MARK: - Sessions (local multi-session history — one JSON file each, no server)

    var sessions: [Session] = []
    private var currentSessionID = UUID()
    private var currentTitle = ""
    private var currentCreatedAt = Date()
    var currentSession: UUID { currentSessionID }

    static var sessionsFolderURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("Council/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var conversationFolderDisplayPath: String {
        guard let dir = Self.sessionsFolderURL else { return "—" }
        return dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
    var conversationFileDisplayPath: String { conversationFolderDisplayPath }

    private func sessionURL(_ id: UUID) -> URL? {
        Self.sessionsFolderURL?.appendingPathComponent("\(id.uuidString).json")
    }
    private static var sessionCoder: (enc: JSONEncoder, dec: JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    func loadSessions() {
        guard let dir = Self.sessionsFolderURL,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let dec = Self.sessionCoder.dec
        var loaded: [Session] = []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f), let s = try? dec.decode(Session.self, from: data) { loaded.append(s) }
        }
        sessions = loaded.sorted { $0.updatedAt > $1.updatedAt }
        if let recent = sessions.first { apply(recent) }
    }

    private var derivedTitle: String {
        let q = (rounds.first?.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "Untitled" : String(q.prefix(48))
    }

    func saveConversation() {
        guard hasSession else { return }
        if currentTitle.isEmpty { currentTitle = derivedTitle }
        let s = Session(id: currentSessionID, title: currentTitle,
                        createdAt: currentCreatedAt, updatedAt: Date(),
                        rounds: rounds, history: history)
        if let url = sessionURL(s.id), let data = try? Self.sessionCoder.enc.encode(s) {
            try? data.write(to: url, options: .atomic)
        }
        sessions.removeAll { $0.id == s.id }
        sessions.insert(s, at: 0)
    }

    private func apply(_ s: Session) {
        currentSessionID = s.id
        currentTitle = s.title
        currentCreatedAt = s.createdAt
        rounds = s.rounds
        history = s.history
        viewingRound = max(0, rounds.count - 1)
        status = [:]
        clearDeliberationErrors()
    }

    func openSession(_ s: Session) {
        guard !anyLoading else { return }   // don't swap rounds out from under a running task
        apply(s)
    }

    func newSession() {
        guard !anyLoading else { return }
        currentSessionID = UUID()
        currentTitle = ""
        currentCreatedAt = Date()
        rounds = []
        viewingRound = 0
        status = [:]
        history = [:]
        clearDeliberationErrors()
    }

    func renameSession(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if id == currentSessionID { currentTitle = t }
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].title = t
        if let url = sessionURL(id), let data = try? Self.sessionCoder.enc.encode(sessions[idx]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func deleteSession(_ id: UUID) {
        // Deleting the active session resets rounds → must not happen mid-generation.
        if id == currentSessionID && anyLoading { return }
        if let url = sessionURL(id) { try? FileManager.default.removeItem(at: url) }
        sessions.removeAll { $0.id == id }
        if id == currentSessionID { newSession() }
    }

    func searchedSessions(_ query: String) -> [Session] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty ? sessions : sessions.filter { $0.searchHaystack.contains(q) }
    }

    func revealConversationFolder() {
        guard let dir = Self.sessionsFolderURL else { return }
        NSWorkspace.shared.open(dir)
    }
}
