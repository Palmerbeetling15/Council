import Foundation

/// The LLM backends a council seat can use.
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case openAI
    case gemini
    case foundationModels

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:           return "Claude"
        case .openAI:           return "GPT (OpenAI)"
        case .gemini:           return "Gemini"
        case .foundationModels: return "Apple (on-device)"
        }
    }

    /// Foundation Models runs on-device, so it needs no API key. Everything else does.
    var requiresAPIKey: Bool {
        self != .foundationModels
    }

    /// Stable identifier used as the Keychain account name for this provider's key.
    var keychainAccount: String {
        "apikey.\(rawValue)"
    }

    /// Default model id per provider. These move fast — update here if an API
    /// rejects the name. (Verified current as of May 2026.)
    var defaultModel: String {
        switch self {
        case .claude:           return "claude-sonnet-4-6"
        case .openAI:           return "gpt-5.4-mini"
        case .gemini:           return "gemini-3.5-flash"
        case .foundationModels: return ""
        }
    }
}
