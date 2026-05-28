import Foundation

/// A uniform interface over every LLM backend. Each provider has its own
/// wire format under the hood, but callers only ever see this one method.
protocol LLMClient {
    func complete(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String
}

/// Human-readable error surfaced to the UI.
enum LLMError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// Picks the right client for a provider. GPT and Gemini share the OpenAI
/// wire format; Claude has its own; Foundation Models is not wired yet.
enum LLMClientFactory {
    static func make(for provider: LLMProvider) -> LLMClient {
        switch provider {
        case .claude:
            return AnthropicClient(model: provider.defaultModel)
        case .openAI:
            return OpenAICompatibleClient(
                endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                model: provider.defaultModel
            )
        case .gemini:
            return OpenAICompatibleClient(
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!,
                model: provider.defaultModel
            )
        case .foundationModels:
            return UnavailableClient(
                reason: "Apple on-device (Foundation Models) yakında — daha yeni bir macOS sürümü gerekiyor."
            )
        }
    }
}

/// Placeholder for backends we haven't wired yet (e.g. on-device Foundation Models).
struct UnavailableClient: LLMClient {
    let reason: String
    func complete(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        throw LLMError.message(reason)
    }
}
