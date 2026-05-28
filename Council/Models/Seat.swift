import Foundation

/// One seat at the council table: a persona paired with an LLM backend.
/// The API key itself is not stored here — it lives in the Keychain,
/// addressed by `provider.keychainAccount`.
struct Seat: Identifiable, Codable {
    let id: Int
    var archetype: Archetype
    var provider: LLMProvider
}
