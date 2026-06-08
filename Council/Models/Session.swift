import Foundation

/// One deliberation round: a question, each advisor's answer, their peer reviews, and the
/// (optional) divergence + synthesis generated for THIS round. Each round keeps its own
/// analyses, so asking a follow-up never wipes an earlier round's work.
struct Round: Codable, Identifiable {
    var id = UUID()
    var question: String
    var answers: [Int: String] = [:]
    var peerReviews: [Int: String] = [:]
    var divergence: String?
    var synthesis: String?
    /// "Divergence verdict" the analyst computes in the SAME divergence call: how much the advisors
    /// agree on the bottom line (0–100), how many distinct camps, and which advisor is the outlier
    /// (a panel name, or nil). Measures agreement, NOT correctness — they can share a blind spot.
    var divergenceScore: Int?
    var divergenceCamps: Int?
    var outlier: String?
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var costUSD: Double = 0
    /// Which provider produced each seat's answer (seat id → panel name), so a reopened session
    /// still shows "CLAUDE" on the panel even if that seat is currently unassigned.
    var answerProviders: [Int: String] = [:]

    /// Seat ids that have a non-empty answer in this round.
    var answeredSeatIDs: Set<Int> { Set(answers.filter { !$0.value.isEmpty }.keys) }

    enum CodingKeys: String, CodingKey {
        case id, question, answers, peerReviews, divergence, synthesis
        case inputTokens, outputTokens, costUSD, answerProviders
    }
    init(question: String) { self.question = question }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        question = (try? c.decode(String.self, forKey: .question)) ?? ""
        answers = (try? c.decode([Int: String].self, forKey: .answers)) ?? [:]
        peerReviews = (try? c.decode([Int: String].self, forKey: .peerReviews)) ?? [:]
        divergence = try? c.decodeIfPresent(String.self, forKey: .divergence)
        synthesis = try? c.decodeIfPresent(String.self, forKey: .synthesis)
        inputTokens = (try? c.decode(Int.self, forKey: .inputTokens)) ?? 0
        outputTokens = (try? c.decode(Int.self, forKey: .outputTokens)) ?? 0
        costUSD = (try? c.decode(Double.self, forKey: .costUSD)) ?? 0
        answerProviders = (try? c.decode([Int: String].self, forKey: .answerProviders)) ?? [:]
    }
}

/// A saved council session — a list of rounds plus each seat's conversation context. Stored
/// locally as one JSON file per session in the app container. No server, no cloud.
struct Session: Codable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var rounds: [Round]
    var history: [Int: [ChatMessage]]

    /// Text used for searching this session (title + every question + every answer).
    var searchHaystack: String {
        var s = title
        for r in rounds {
            s += " " + r.question
            for a in r.answers.values { s += " " + a }
        }
        return s.lowercased()
    }

    var totalCostUSD: Double { rounds.reduce(0) { $0 + $1.costUSD } }
}
