import Foundation

/// An image attached to a question. Re-encoded to PNG before it reaches here.
/// `Sendable` so it can cross into the parallel task group. The image rides only on the
/// transient request; only the text question is appended to saved history, so session
/// files on disk never carry image bytes.
struct ImageAttachment: Sendable, Codable {
    let data: Data
    let mediaType: String           // e.g. "image/png"
    var base64: String { data.base64EncodedString() }
}

/// One message in a conversation. `system` carries instructions; `user`/`assistant`
/// carry the back-and-forth. An image may ride on a user message. This is the unit the
/// whole deliberation pipeline is built on — multi-turn history, and (soon) feeding each
/// model the others' answers for peer review.
struct ChatMessage: Sendable, Codable {
    enum Role: String, Sendable, Codable { case system, user, assistant }
    let role: Role
    let text: String
    var image: ImageAttachment? = nil

    static func system(_ t: String) -> ChatMessage { .init(role: .system, text: t) }
    static func user(_ t: String, image: ImageAttachment? = nil) -> ChatMessage { .init(role: .user, text: t, image: image) }
    static func assistant(_ t: String) -> ChatMessage { .init(role: .assistant, text: t) }
}

/// A streamed piece of a response: a text delta, or the final token usage.
enum StreamChunk: Sendable {
    case text(String)
    case usage(input: Int, output: Int)
}

/// A uniform interface over every LLM backend. Each provider has its own wire format
/// under the hood, but callers only ever see these methods.
protocol LLMClient {
    /// Token-by-token stream. Yields text deltas as they arrive, then a usage chunk.
    func stream(messages: [ChatMessage], apiKey: String) -> AsyncThrowingStream<StreamChunk, Error>
    /// Cheap key check: makes a tiny authenticated call. Returns normally if the key
    /// works, throws a clear `LLMError` if it's invalid / out of balance / unusable.
    func validate(apiKey: String) async throws
}

/// Turns the HTTP status + body of a tiny test call into a clear, user-facing key error.
enum KeyValidation {
    static func interpret(status: Int, body: Data) throws {
        if (200..<300).contains(status) { return }
        let text = (String(data: body, encoding: .utf8) ?? "").lowercased()
        let balance = text.contains("credit") || text.contains("balance")
            || text.contains("quota") || text.contains("billing") || text.contains("insufficient")
        let invalid = text.contains("api key") || text.contains("api_key")
            || text.contains("invalid") || text.contains("unauthor")
        switch status {
        case 401, 403:
            throw LLMError.message("API key is invalid or unauthorized.")
        case 429:
            throw LLMError.message("Quota / balance exceeded (rate limit).")
        default:
            if balance { throw LLMError.message("Insufficient balance or quota.") }
            if invalid { throw LLMError.message("Invalid API key.") }
            throw LLMError.message("Couldn't verify (HTTP \(status)).")
        }
    }
}

/// Human-readable error surfaced to the UI.
enum LLMError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// Picks the right client for a provider. Claude has its own wire format; everything else
/// (GPT, Gemini, DeepSeek, Grok, Mistral, Perplexity, OpenRouter, local Ollama) speaks the
/// OpenAI `/chat/completions` format and shares one client, differing only by endpoint.
enum LLMClientFactory {
    static func make(for provider: LLMProvider, model: String,
                     temperature: Double? = nil, maxTokens: Int? = nil) -> LLMClient {
        // Fall back to the provider default if a blank model id ever slips through.
        let model = model.isEmpty ? provider.defaultModel : model
        if provider == .claude {
            return AnthropicClient(model: model, temperature: temperature, maxTokens: maxTokens)
        }
        if let endpoint = provider.openAIEndpoint {
            return OpenAICompatibleClient(endpoint: endpoint, model: model,
                                          temperature: temperature, maxTokens: maxTokens)
        }
        return UnavailableClient(reason: "\(provider.displayName) isn't available yet.")
    }
}

/// Placeholder for backends we haven't wired yet (e.g. on-device Foundation Models).
struct UnavailableClient: LLMClient {
    let reason: String
    func stream(messages: [ChatMessage], apiKey: String) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: LLMError.message(reason)) }
    }
    func validate(apiKey: String) async throws {
        throw LLMError.message(reason)
    }
}
