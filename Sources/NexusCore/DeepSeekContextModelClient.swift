import Foundation

public final class DeepSeekContextModelClient: ContextModelClient, @unchecked Sendable {
    public static let flashModel = "deepseek-v4-flash"
    public static let proModel = "deepseek-v4-pro"
    public static let defaultModel = flashModel
    public let configuration: ContextModelConfiguration

    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!,
        model: String = DeepSeekContextModelClient.defaultModel
    ) {
        self.session = session
        self.endpoint = endpoint
        self.configuration = ContextModelConfiguration(provider: .deepSeek, model: model)
    }

    public func generate(request: ContextModelRequest, apiKey: String) async throws -> ContextPackContent {
        for attempt in 0..<2 {
            do {
                return try await generateOnce(
                    request: request,
                    apiKey: apiKey,
                    compactOutput: attempt > 0
                )
            } catch {
                guard attempt == 0, shouldRetry(error) else { throw error }
            }
        }
        throw ContextModelError.emptyResponse(.deepSeek)
    }

    public func validateConnection(apiKey: String) async throws {
        for attempt in 0..<2 {
            do {
                let data = try await performRequest(
                    body: connectionProbeBody(),
                    apiKey: apiKey
                )
                let output = try extractOutputText(from: data)
                guard let outputData = output.data(using: .utf8),
                    let rawObject = try? JSONSerialization.jsonObject(with: outputData),
                    let object = rawObject as? [String: Any],
                    object["ok"] as? Bool == true
                else {
                    throw ContextModelError.invalidResponse(
                        .deepSeek,
                        "connection probe did not return ok"
                    )
                }
                return
            } catch {
                guard attempt == 0, shouldRetry(error) else { throw error }
            }
        }
    }

    private func generateOnce(
        request: ContextModelRequest,
        apiKey: String,
        compactOutput: Bool
    ) async throws -> ContextPackContent {
        let data = try await performRequest(
            body: try requestBody(for: request, compactOutput: compactOutput),
            apiKey: apiKey
        )
        let output = try extractOutputText(from: data)
        return try ContextModelPrompt.decodedContent(
            from: output,
            request: request,
            provider: .deepSeek
        )
    }

    private func performRequest(
        body: [String: Any],
        apiKey: String
    ) async throws -> Data {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 90
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: body,
            options: [.sortedKeys]
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ContextModelError.invalidResponse(.deepSeek, "missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = ContextModelPrompt.errorMessage(from: data)
            switch http.statusCode {
            case 401, 403:
                throw ContextModelError.invalidAPIKey(.deepSeek)
            case 429:
                throw ContextModelError.rateLimited(.deepSeek)
            default:
                throw ContextModelError.httpStatus(.deepSeek, http.statusCode, detail)
            }
        }
        return data
    }

    private func requestBody(
        for request: ContextModelRequest,
        compactOutput: Bool
    ) throws -> [String: Any] {
        [
            "model": configuration.model,
            "messages": [
                [
                    "role": "system",
                    "content": ContextModelPrompt.systemPrompt(
                        language: request.language,
                        compactOutput: compactOutput
                    ),
                ],
                [
                    "role": "user",
                    "content": try ContextModelPrompt.userPrompt(for: request, provider: .deepSeek),
                ],
            ],
            "response_format": ["type": "json_object"],
            "thinking": ["type": "disabled"],
            "temperature": 0.2,
            "max_tokens": 12_000,
            "stream": false,
        ]
    }

    private func connectionProbeBody() -> [String: Any] {
        [
            "model": configuration.model,
            "messages": [
                [
                    "role": "system",
                    "content": "Return exactly one valid JSON object and no other text.",
                ],
                [
                    "role": "user",
                    "content": "Return this JSON object: {\"ok\": true}",
                ],
            ],
            "response_format": ["type": "json_object"],
            "thinking": ["type": "disabled"],
            "temperature": 0,
            "max_tokens": 64,
            "stream": false,
        ]
    }

    private func extractOutputText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let choice = choices.first
        else {
            throw ContextModelError.invalidResponse(.deepSeek, "response did not contain a choice")
        }
        if choice["finish_reason"] as? String == "length" {
            throw ContextModelError.outputTruncated(.deepSeek)
        }
        guard let message = choice["message"] as? [String: Any],
            let content = message["content"] as? String,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ContextModelError.emptyResponse(.deepSeek)
        }
        return content
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let preparationError = error as? ContextPreparationError {
            if case .invalidModelOutput = preparationError {
                return true
            }
            return false
        }
        guard let modelError = error as? ContextModelError else {
            return false
        }
        switch modelError {
        case .emptyResponse(.deepSeek), .invalidResponse(.deepSeek, _),
            .outputTruncated(.deepSeek):
            return true
        default:
            return false
        }
    }
}
