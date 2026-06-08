import Foundation

/// The LLM backends a council seat can use. Most speak the OpenAI `/chat/completions`
/// wire format, so they share `OpenAICompatibleClient`; Claude has its own; Ollama runs
/// locally with no key; Foundation Models is on-device and not wired yet.
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case openAI
    case gemini
    case deepSeek
    case grok
    case mistral
    case perplexity
    case openRouter
    case ollama
    case foundationModels

    var id: String { rawValue }

    /// Providers offered in the seat picker.
    static var selectable: [LLMProvider] {
        [.claude, .openAI, .gemini, .deepSeek, .grok, .mistral, .perplexity, .openRouter, .ollama, .foundationModels]
    }

    var displayName: String {
        switch self {
        case .claude:           return "Claude"
        case .openAI:           return "GPT (OpenAI)"
        case .gemini:           return "Gemini"
        case .deepSeek:         return "DeepSeek"
        case .grok:             return "Grok (xAI)"
        case .mistral:          return "Mistral"
        case .perplexity:       return "Perplexity"
        case .openRouter:       return "OpenRouter"
        case .ollama:           return "Ollama (local)"
        case .foundationModels: return "Apple (on-device)"
        }
    }

    /// Short label shown on the terminal panels.
    var panelName: String {
        switch self {
        case .claude:           return "Claude"
        case .openAI:           return "GPT"
        case .gemini:           return "Gemini"
        case .deepSeek:         return "DeepSeek"
        case .grok:             return "Grok"
        case .mistral:          return "Mistral"
        case .perplexity:       return "Perplexity"
        case .openRouter:       return "OpenRouter"
        case .ollama:           return "Ollama"
        case .foundationModels: return "Apple"
        }
    }

    /// A one-line note shown next to the name in the picker (nil = nothing extra).
    var pickerNote: String? {
        switch self {
        case .ollama:     return "local · no key"
        case .foundationModels: return "on-device · free · no key"
        case .openRouter: return "one key · many models"
        case .perplexity: return "web-grounded"
        case .deepSeek:   return "cheap · reasoning"
        default:          return nil
        }
    }

    /// Ollama runs locally and Foundation Models on-device, so they need no API key. Others do.
    var requiresAPIKey: Bool {
        self != .ollama && self != .foundationModels
    }

    /// Whether this provider's models accept image input. Used to avoid sending an image to a
    /// text-only model (which would hard-fail with HTTP 400). For a given seat we also check the
    /// model id, since within a provider only some models are multimodal.
    func supportsVision(model: String) -> Bool {
        let m = model.lowercased()
        switch self {
        case .claude, .openAI, .gemini:
            return true   // current flagship Claude / GPT / Gemini families are multimodal
        case .openRouter:
            // OpenRouter routes to many models — assume vision only for known multimodal families.
            return m.contains("gpt") || m.contains("claude") || m.contains("gemini") || m.contains("llama-4") || m.contains("vision")
        case .grok:
            return m.contains("vision") || m.contains("grok-4")
        case .ollama:
            return m.contains("llava") || m.contains("vision") || m.contains("gemma3") || m.contains("llama3.2-vision")
        case .deepSeek, .mistral, .perplexity, .foundationModels:
            return false  // text-only in practice
        }
    }

    /// Stable identifier used as the Keychain account name for this provider's key.
    var keychainAccount: String { "apikey.\(rawValue)" }

    /// The provider's official API-key console — shown as a "where do I get a key?" link in the
    /// key-entry step. nil for local/on-device backends that need no key.
    var consoleURL: URL? {
        switch self {
        case .claude:     return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI:     return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:     return URL(string: "https://aistudio.google.com/apikey")
        case .deepSeek:   return URL(string: "https://platform.deepseek.com/api_keys")
        case .grok:       return URL(string: "https://console.x.ai")
        case .mistral:    return URL(string: "https://console.mistral.ai/api-keys")
        case .perplexity: return URL(string: "https://www.perplexity.ai/settings/api")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .ollama, .foundationModels: return nil
        }
    }

    /// OpenAI-compatible `/chat/completions` endpoint. nil for backends that don't use the
    /// generic client (Claude has its own; Foundation Models isn't networked).
    var openAIEndpoint: URL? {
        switch self {
        case .openAI:     return URL(string: "https://api.openai.com/v1/chat/completions")
        case .gemini:     return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        case .deepSeek:   return URL(string: "https://api.deepseek.com/v1/chat/completions")
        case .grok:       return URL(string: "https://api.x.ai/v1/chat/completions")
        case .mistral:    return URL(string: "https://api.mistral.ai/v1/chat/completions")
        case .perplexity: return URL(string: "https://api.perplexity.ai/chat/completions")
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")
        case .ollama:     return URL(string: "http://localhost:11434/v1/chat/completions")
        case .claude, .foundationModels: return nil
        }
    }

    /// GET endpoint that lists this provider's available models, so the picker can offer what the
    /// user can actually use instead of a fixed suggestion list. Ollama uses /api/tags; OpenRouter's
    /// /models is public; everything else is the chat base with `/models` (queried with the key).
    var modelsEndpoint: URL? {
        switch self {
        case .claude:           return URL(string: "https://api.anthropic.com/v1/models")
        case .ollama:           return URL(string: "http://localhost:11434/api/tags")
        case .foundationModels: return nil
        default:
            return openAIEndpoint.flatMap {
                URL(string: $0.absoluteString.replacingOccurrences(of: "chat/completions", with: "models"))
            }
        }
    }

    /// Default model id per provider. These move fast — update here if an API rejects the name.
    var defaultModel: String {
        switch self {
        case .claude:           return "claude-sonnet-4-6"
        case .openAI:           return "gpt-5.4-mini"
        case .gemini:           return "gemini-3.5-flash"
        case .deepSeek:         return "deepseek-chat"
        case .grok:             return "grok-4.3"
        case .mistral:          return "mistral-large-latest"
        case .perplexity:       return "sonar"
        case .openRouter:       return "openai/gpt-5.4-mini"
        case .ollama:           return "llama3.2"
        case .foundationModels: return "on-device"
        }
    }

    /// Suggested model ids for the picker. Just shortcuts — the user can type any id by hand,
    /// so an outdated list never blocks them.
    var modelOptions: [String] {
        switch self {
        case .claude:           return ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5"]
        case .openAI:           return ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini"]
        case .gemini:           return ["gemini-3.5-pro", "gemini-3.5-flash"]
        case .deepSeek:         return ["deepseek-chat", "deepseek-reasoner"]
        case .grok:             return ["grok-4.3", "grok-4.1-fast", "grok-4-fast-reasoning"]
        case .mistral:          return ["mistral-large-latest", "mistral-medium-latest", "mistral-small-latest"]
        case .perplexity:       return ["sonar", "sonar-pro", "sonar-reasoning"]
        case .openRouter:       return ["openai/gpt-5.4", "anthropic/claude-sonnet-4-6",
                                        "google/gemini-3.5-pro", "deepseek/deepseek-chat",
                                        "meta-llama/llama-4-70b-instruct"]
        case .ollama:           return ["llama3.2", "llama3.3", "qwen2.5", "deepseek-r1", "gemma3", "mistral", "phi4"]
        case .foundationModels: return ["on-device"]
        }
    }

    /// Rough USD price per 1M tokens (input, output). Approximate — used only for a calm cost
    /// *estimate*; the user pays the provider directly with their own key. OpenRouter varies by
    /// model, so its number is a middling placeholder.
    var pricePer1MInput: Double {
        switch self {
        case .claude:           return 3.0
        case .openAI:           return 2.5
        case .gemini:           return 0.3
        case .deepSeek:         return 0.3
        case .grok:             return 2.0
        case .mistral:          return 2.0
        case .perplexity:       return 1.0
        case .openRouter:       return 1.0
        case .ollama:           return 0
        case .foundationModels: return 0
        }
    }
    var pricePer1MOutput: Double {
        switch self {
        case .claude:           return 15.0
        case .openAI:           return 10.0
        case .gemini:           return 2.5
        case .deepSeek:         return 1.2
        case .grok:             return 10.0
        case .mistral:          return 6.0
        case .perplexity:       return 1.0
        case .openRouter:       return 3.0
        case .ollama:           return 0
        case .foundationModels: return 0
        }
    }
}
