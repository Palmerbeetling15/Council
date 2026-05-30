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
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var costUSD: Double = 0

    /// Seat ids that have a non-empty answer in this round.
    var answeredSeatIDs: Set<Int> { Set(answers.filter { !$0.value.isEmpty }.keys) }
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
