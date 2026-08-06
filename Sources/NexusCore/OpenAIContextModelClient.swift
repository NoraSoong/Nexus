import Foundation

public final class OpenAIContextModelClient: ContextModelClient, @unchecked Sendable {
    public static let defaultModel = "gpt-5.4-mini"
    public let configuration: ContextModelConfiguration

    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        model: String = OpenAIContextModelClient.defaultModel
    ) {
        self.session = session
        self.endpoint = endpoint
        self.configuration = ContextModelConfiguration(provider: .openAI, model: model)
    }

    public func generate(request: ContextModelRequest, apiKey: String) async throws -> ContextPackContent {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 90
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: try requestBody(for: request),
            options: [.sortedKeys]
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ContextModelError.invalidResponse(.openAI, "missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = ContextModelPrompt.errorMessage(from: data)
            switch http.statusCode {
            case 401, 403:
                throw ContextModelError.invalidAPIKey(.openAI)
            case 429:
                throw ContextModelError.rateLimited(.openAI)
            default:
                throw ContextModelError.httpStatus(.openAI, http.statusCode, detail)
            }
        }

        let outputText = try extractOutputText(from: data)
        return try ContextModelPrompt.decodedContent(
            from: outputText,
            request: request,
            provider: .openAI
        )
    }

    private func requestBody(for request: ContextModelRequest) throws -> [String: Any] {
        [
            "model": configuration.model,
            "store": false,
            "max_output_tokens": 6_000,
            "input": [
                [
                    "role": "system",
                    "content": ContextModelPrompt.systemPrompt(language: request.language),
                ],
                [
                    "role": "user",
                    "content": try ContextModelPrompt.userPrompt(for: request, provider: .openAI),
                ],
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "nexus_context_pack",
                    "description": "A concise, source-grounded software work context pack for human review.",
                    "strict": true,
                    "schema": ContextModelPrompt.responseSchema(),
                ]
            ],
        ]
    }

    private func extractOutputText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ContextModelError.invalidResponse(.openAI, "response was not a JSON object")
        }
        if let outputText = object["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }
        guard let output = object["output"] as? [[String: Any]] else {
            throw ContextModelError.emptyResponse(.openAI)
        }
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if part["type"] as? String == "refusal" {
                    throw ContextModelError.refusal(.openAI, part["refusal"] as? String ?? "request refused")
                }
                if part["type"] as? String == "output_text", let text = part["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        throw ContextModelError.emptyResponse(.openAI)
    }
}
