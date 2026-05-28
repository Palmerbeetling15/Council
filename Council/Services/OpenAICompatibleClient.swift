import Foundation

/// Talks to any OpenAI-style `/chat/completions` endpoint. Used for both
/// GPT (api.openai.com) and Gemini (Google's OpenAI-compatible endpoint).
struct OpenAICompatibleClient: LLMClient {
    let endpoint: URL
    let model: String

    func complete(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = RequestBody(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.message("HTTP \(http.statusCode): \(detail.prefix(300))")
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw LLMError.message("Boş cevap döndü.")
        }
        return text
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct ResponseBody: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
    }
}
