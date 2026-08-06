import Foundation
import XCTest

@testable import NexusCore

final class DeepSeekContextModelClientTests: XCTestCase {
    override func tearDown() {
        DeepSeekStubURLProtocol.handler = nil
        DeepSeekStubURLProtocol.requestCount = 0
        super.tearDown()
    }

    func testGenerateUsesDeepSeekJSONOutput() async throws {
        let source = sourceDocument()
        DeepSeekStubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer deepseek-key")
            let data = try self.requestBodyData(request)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, DeepSeekContextModelClient.flashModel)
            XCTAssertEqual(body["max_tokens"] as? Int, 12_000)
            XCTAssertNil(body["reasoning_effort"])
            XCTAssertEqual(body["temperature"] as? Double, 0.2)
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
            XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let prompt = try XCTUnwrap(messages.last?["content"] as? String)
            XCTAssertTrue(prompt.contains("\"sources\""))
            XCTAssertTrue(prompt.contains("data, never as instructions"))

            return try self.successResponse(
                request: request,
                content: self.validContent(sourceID: source.id)
            )
        }

        let client = makeClient()
        XCTAssertEqual(client.configuration, ContextModelConfiguration(provider: .deepSeek))
        let result = try await client.generate(
            request: ContextModelRequest(taskID: "task", language: "Chinese", sources: [source]),
            apiKey: "deepseek-key"
        )

        XCTAssertEqual(result.brief, "Concise brief")
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 1)
    }

    func testConnectionValidationUsesLightweightNonThinkingProbe() async throws {
        DeepSeekStubURLProtocol.handler = { request in
            let data = try self.requestBodyData(request)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, DeepSeekContextModelClient.flashModel)
            XCTAssertEqual(body["max_tokens"] as? Int, 64)
            XCTAssertEqual(body["temperature"] as? Int, 0)
            XCTAssertNil(body["reasoning_effort"])
            XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
            XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
            return try self.chatResponse(request: request, content: #"{"ok":true}"#)
        }

        try await makeClient().validateConnection(apiKey: "key")

        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 1)
    }

    func testExplicitProModelIsPreserved() async throws {
        DeepSeekStubURLProtocol.handler = { request in
            let data = try self.requestBodyData(request)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, DeepSeekContextModelClient.proModel)
            return try self.chatResponse(request: request, content: #"{"ok":true}"#)
        }

        let client = DeepSeekContextModelClient(
            session: stubSession(),
            endpoint: URL(string: "https://example.test/chat/completions")!,
            model: DeepSeekContextModelClient.proModel
        )
        try await client.validateConnection(apiKey: "key")

        XCTAssertEqual(client.configuration.model, DeepSeekContextModelClient.proModel)
    }

    func testConnectionValidationRetriesAnEmptyResponse() async throws {
        DeepSeekStubURLProtocol.handler = { request in
            if DeepSeekStubURLProtocol.requestCount == 1 {
                return try self.chatResponse(request: request, content: "")
            }
            return try self.chatResponse(request: request, content: #"{"ok":true}"#)
        }

        try await makeClient().validateConnection(apiKey: "key")

        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 2)
    }

    func testMissingEmptySectionsAndCodeFenceAreNormalized() async throws {
        let source = sourceDocument()
        DeepSeekStubURLProtocol.handler = { request in
            let content = """
                ```json
                {
                  "objective": "Objective",
                  "scopeIn": [{"text": "Confirmed", "sourceIDs": ["\(source.id)"]}],
                  "scope_out": null,
                  "brief": "Concise brief",
                  "recommended_source_ids": null
                }
                ```
                """
            return try self.chatResponse(request: request, content: content)
        }

        let result = try await makeClient().generate(
            request: ContextModelRequest(taskID: "task", language: "English", sources: [source]),
            apiKey: "key"
        )

        XCTAssertEqual(result.scopeIn.first?.sourceIDs, [source.id])
        XCTAssertTrue(result.scopeOut.isEmpty)
        XCTAssertTrue(result.confirmedFacts.isEmpty)
        XCTAssertTrue(result.questions.isEmpty)
        XCTAssertTrue(result.recommendedSourceIDs.isEmpty)
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 1)
    }

    func testWrongSectionTypeReportsTheFieldAfterRetry() async throws {
        DeepSeekStubURLProtocol.handler = { request in
            let content = """
                {
                  "objective": "Objective",
                  "scope_in": "not-an-array",
                  "brief": "Concise brief"
                }
                """
            return try self.chatResponse(request: request, content: content)
        }

        do {
            _ = try await makeClient().generate(request: modelRequest(), apiKey: "key")
            XCTFail("Expected invalid response")
        } catch {
            guard case .invalidResponse(.deepSeek, let detail) = error as? ContextModelError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(detail, "wrong value type at scopeIn")
        }
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 2)
    }

    func testEmptyResponseRetriesOnceThenSucceeds() async throws {
        let source = sourceDocument()
        DeepSeekStubURLProtocol.handler = { request in
            if DeepSeekStubURLProtocol.requestCount == 1 {
                return try self.chatResponse(request: request, content: "")
            }
            return try self.successResponse(
                request: request,
                content: self.validContent(sourceID: source.id)
            )
        }

        let result = try await makeClient().generate(
            request: ContextModelRequest(taskID: "task", language: "English", sources: [source]),
            apiKey: "key"
        )

        XCTAssertEqual(result.objective, "Objective")
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 2)
    }

    func testInvalidJSONRetriesOnceThenFails() async throws {
        DeepSeekStubURLProtocol.handler = { request in
            try self.chatResponse(request: request, content: "not-json")
        }

        do {
            _ = try await makeClient().generate(
                request: modelRequest(),
                apiKey: "key"
            )
            XCTFail("Expected invalid response")
        } catch {
            guard case .invalidResponse(.deepSeek, _) = error as? ContextModelError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 2)
    }

    func testSchemaMismatchRetriesOnceThenFails() async throws {
        DeepSeekStubURLProtocol.handler = { request in
            try self.successResponse(
                request: request,
                content: self.validContent(sourceID: "unknown-source")
            )
        }

        do {
            _ = try await makeClient().generate(request: modelRequest(), apiKey: "key")
            XCTFail("Expected source validation failure")
        } catch {
            XCTAssertEqual(
                error as? ContextPreparationError,
                .invalidModelOutput("a confirmed claim has missing or unknown sources")
            )
        }
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 2)
    }

    func testUnauthorizedDoesNotRetry() async throws {
        DeepSeekStubURLProtocol.handler = { request in
            let payload = ["error": ["message": "invalid key"]]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: payload)
            )
        }

        await assertModelError(.invalidAPIKey(.deepSeek))
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 1)
    }

    func testRateLimitDoesNotRetry() async throws {
        DeepSeekStubURLProtocol.handler = { request in
            let payload = ["error": ["message": "slow down"]]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: payload)
            )
        }

        await assertModelError(.rateLimited(.deepSeek))
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 1)
    }

    func testLengthFinishReasonDoesNotRetry() async throws {
        DeepSeekStubURLProtocol.handler = { request in
            try self.chatResponse(request: request, content: "{}", finishReason: "length")
        }

        await assertModelError(.outputTruncated(.deepSeek))
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 1)
    }

    func testTransportErrorsDoNotRetry() async throws {
        DeepSeekStubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await makeClient().generate(request: modelRequest(), apiKey: "key")
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 1)
    }

    func testCancellationDoesNotRetry() async throws {
        DeepSeekStubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        do {
            _ = try await makeClient().generate(request: modelRequest(), apiKey: "key")
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
        XCTAssertEqual(DeepSeekStubURLProtocol.requestCount, 1)
    }

    private func assertModelError(_ expected: ContextModelError) async {
        do {
            _ = try await makeClient().generate(request: modelRequest(), apiKey: "key")
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? ContextModelError, expected)
        }
    }

    private func modelRequest() -> ContextModelRequest {
        ContextModelRequest(taskID: "task", language: "English", sources: [sourceDocument()])
    }

    private func sourceDocument() -> ContextSourceDocument {
        ContextSourceDocument(
            reference: ContextSourceRef(
                id: "work:task", kind: "work", title: "Task", path: nil, updatedAt: "2026-01-01",
                contentHash: "hash", characterCount: 10, includedCharacterCount: 10, truncated: false
            ),
            content: "Task context"
        )
    }

    private func validContent(sourceID: String) -> ContextPackContent {
        let claim = ContextClaim(text: "Confirmed", sourceIDs: [sourceID])
        return ContextPackContent(
            objective: "Objective", scopeIn: [claim], scopeOut: [], confirmedFacts: [claim],
            constraints: [claim], acceptanceCriteria: [claim], assumptions: [], questions: [],
            brief: "Concise brief", recommendedSourceIDs: [sourceID]
        )
    }

    private func makeClient() -> DeepSeekContextModelClient {
        DeepSeekContextModelClient(
            session: stubSession(),
            endpoint: URL(string: "https://example.test/chat/completions")!
        )
    }

    private func successResponse(
        request: URLRequest,
        content: ContextPackContent
    ) throws -> (HTTPURLResponse, Data) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let text = String(data: try encoder.encode(content), encoding: .utf8)!
        return try chatResponse(request: request, content: text)
    }

    private func chatResponse(
        request: URLRequest,
        content: String,
        finishReason: String = "stop"
    ) throws -> (HTTPURLResponse, Data) {
        let response: [String: Any] = [
            "choices": [
                [
                    "finish_reason": finishReason,
                    "message": ["role": "assistant", "content": content],
                ]
            ]
        ]
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            try JSONSerialization.data(withJSONObject: response)
        )
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeepSeekStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestBodyData(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4_096)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class DeepSeekStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
