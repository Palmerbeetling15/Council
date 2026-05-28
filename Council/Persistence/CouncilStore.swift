import Foundation
import Observation

/// Central app state: the three council seats, their saved configuration,
/// and the latest answer from each seat.
@Observable
final class CouncilStore {
    var seats: [Seat]
    var responses: [Int: SeatResponse] = [:]

    private let seatsKey = "council.seats"

    init() {
        if let data = UserDefaults.standard.data(forKey: seatsKey),
           let saved = try? JSONDecoder().decode([Seat].self, from: data),
           saved.count == 3 {
            seats = saved
        } else {
            seats = [
                Seat(id: 0, archetype: .sage,       provider: .claude),
                Seat(id: 1, archetype: .strategist, provider: .openAI),
                Seat(id: 2, archetype: .scientist,  provider: .gemini)
            ]
        }
    }

    /// Persist seat choices (not keys) to UserDefaults.
    func saveSeats() {
        if let data = try? JSONEncoder().encode(seats) {
            UserDefaults.standard.set(data, forKey: seatsKey)
        }
    }

    /// True when every seat that needs an API key has one stored in the Keychain.
    var isConfigured: Bool {
        seats.allSatisfy { seat in
            guard seat.provider.requiresAPIKey else { return true }
            let key = try? KeychainStore.read(account: seat.provider.keychainAccount)
            return (key?.isEmpty == false)
        }
    }

    /// Ask the whole council a question — every seat answers in parallel.
    @MainActor
    func ask(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        for seat in seats { responses[seat.id] = .loading }

        await withTaskGroup(of: (Int, SeatResponse).self) { group in
            for seat in seats {
                group.addTask { await Self.answer(for: seat, query: trimmed) }
            }
            for await (id, result) in group {
                responses[id] = result
            }
        }
    }

    private static func answer(for seat: Seat, query: String) async -> (Int, SeatResponse) {
        do {
            var apiKey = ""
            if seat.provider.requiresAPIKey {
                guard let stored = try KeychainStore.read(account: seat.provider.keychainAccount),
                      !stored.isEmpty else {
                    return (seat.id, .failed("API key bulunamadı."))
                }
                apiKey = stored
            }
            let client = LLMClientFactory.make(for: seat.provider)
            let text = try await client.complete(
                systemPrompt: seat.archetype.systemPrompt,
                userPrompt: query,
                apiKey: apiKey
            )
            return (seat.id, .text(text))
        } catch {
            return (seat.id, .failed(error.localizedDescription))
        }
    }
}

/// Per-seat answer state, shown in the UI.
enum SeatResponse {
    case idle
    case loading
    case text(String)
    case failed(String)
}
