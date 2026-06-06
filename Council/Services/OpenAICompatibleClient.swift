import Foundation

/// Talks to any OpenAI-style `/chat/completions` endpoint. Used for both
/// GPT (api.openai.com) and Gemini (Google's OpenAI-compatible endpoint).
struct OpenAICompatibleClient: LLMClient {
    let endpoint: URL
    let model: String
    var temperature: Double? = nil
    var maxTokens: Int? = nil

    func validate(apiKey: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Smallest possible call: 1 output token. We only care about the HTTP status.
        let body = RequestBody(model: model,
                               messages: [.init(role: "user", content: .text("Hi"))],
                               max_tokens: 1)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try KeyValidation.interpret(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    func stream(messages: [ChatMessage], apiKey: String) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                    let wire: [RequestBody.Message] = messages.map { msg in
                        if let image = msg.image, msg.role == .user {
                            return RequestBody.Message(role: msg.role.rawValue, content: .parts([
                                Part(type: "text", text: msg.text),
                                Part(type: "image_url", image_url: .init(url: "data:\(image.mediaType);base64,\(image.base64)"))
                            ]))
                        }
                        return RequestBody.Message(role: msg.role.rawValue, content: .text(msg.text))
                    }
                    let body = RequestBody(model: model, messages: wire, max_tokens: maxTokens, stream: true,
                                           stream_options: .init(include_usage: true), temperature: temperature)
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var errBody = ""
                        for try await line in bytes.lines { errBody += line; if errBody.count > 1200 { break } }
                        throw LLMError.message(HTTPError.describe(http.statusCode, errBody))
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let ev = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }
                        if let c = ev.choices?.first?.delta?.content, !c.isEmpty { continuation.yield(.text(c)) }
                        if let u = ev.usage {
                            continuation.yield(.usage(input: u.prompt_tokens ?? 0, output: u.completion_tokens ?? 0))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct StreamEvent: Decodable {
        let choices: [Choice]?
        let usage: Usage?
        struct Choice: Decodable { let delta: Delta? }
        struct Delta: Decodable { let content: String? }
        struct Usage: Decodable { let prompt_tokens: Int?; let completion_tokens: Int? }
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        var max_tokens: Int? = nil          // omitted when nil; set to 1 for validation
        var stream: Bool? = nil
        var stream_options: StreamOptions? = nil
        var temperature: Double? = nil
        struct Message: Encodable { let role: String; let content: Content }
        struct StreamOptions: Encodable { let include_usage: Bool }
    }

    /// Either a plain string (text-only) or an array of parts (with image).
    private enum Content: Encodable {
        case text(String)
        case parts([Part])
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .text(let s):   try c.encode(s)
            case .parts(let p):  try c.encode(p)
            }
        }
    }

    private struct Part: Encodable {
        let type: String
        var text: String? = nil
        var image_url: ImageURL? = nil      // nil fields are omitted by the synthesized encoder
    }

    private struct ImageURL: Encodable { let url: String }
}
