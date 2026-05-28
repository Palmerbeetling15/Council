import Foundation

/// Talks to Anthropic's native Messages API (`/v1/messages`), which uses a
/// different shape than OpenAI: `x-api-key` + `anthropic-version` headers,
/// a top-level `system` field, and a `content` array in the response.
struct AnthropicClient: LLMClient {
    let model: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func complete(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = RequestBody(
            model: model,
            max_tokens: 1024,
            system: systemPrompt,
            messages: [.init(role: "user", content: userPrompt)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.message("HTTP \(http.statusCode): \(detail.prefix(300))")
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.content.compactMap(\.text).joined()
        guard !text.isEmpty else { throw LLMError.message("Boş cevap döndü.") }
        return text
    }

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct ResponseBody: Decodable {
        let content: [Block]
        struct Block: Decodable { let type: String; let text: String? }
    }
}
