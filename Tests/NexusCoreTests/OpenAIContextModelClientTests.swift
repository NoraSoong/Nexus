import Foundation
import XCTest

@testable import NexusCore

final class OpenAIContextModelClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.requestCount = 0
        super.tearDown()
    }

    func testGenerateUsesResponsesStructuredOutput() async throws {
        let source = sourceDocument()
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/responses")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try self.requestBodyData(request)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["store"] as? Bool, false)
            let text = try XCTUnwrap(object["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            let input = try XCTUnwrap(object["input"] as? [[String: Any]])
            let userPrompt = try XCTUnwrap(input.last?["content"] as? String)
            XCTAssertTrue(userPrompt.contains("\"sources\""))
            XCTAssertFalse(userPrompt.contains("<source"))

            let content = self.validContent(sourceID: source.id)
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let output = String(data: try encoder.encode(content), encoding: .utf8)!
            let response: [String: Any] = [
                "output": [
                    [
                        "type": "message",
                        "content": [["type": "output_text", "text": output]],
                    ]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }

        let client = OpenAIContextModelClient(
            session: stubSession(), endpoint: URL(string: "https://example.test/v1/responses")!, model: "test-model")
        XCTAssertEqual(client.configuration, ContextModelConfiguration(provider: .openAI, model: "test-model"))
        let result = try await client.generate(
            request: ContextModelRequest(taskID: "task", language: "Chinese", sources: [source]),
            apiKey: "test-key"
        )
        XCTAssertEqual(result.brief, "Concise brief")
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testUnauthorizedResponseMapsToInvalidAPIKey() async throws {
        StubURLProtocol.handler = { request in
            let payload = ["error": ["message": "invalid key"]]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: payload)
            )
        }
        let client = OpenAIContextModelClient(
            session: stubSession(), endpoint: URL(string: "https://example.test/v1/responses")!)
        do {
            _ = try await client.generate(
                request: ContextModelRequest(taskID: "task", language: "English", sources: [sourceDocument()]),
                apiKey: "bad-key"
            )
            XCTFail("Expected invalid API key error")
        } catch {
            XCTAssertEqual(error as? ContextModelError, .invalidAPIKey(.openAI))
        }
    }

    func testRateLimitMapsToRateLimited() async throws {
        StubURLProtocol.handler = { request in
            let payload = ["error": ["message": "slow down"]]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: payload)
            )
        }
        await assertModelError(.rateLimited(.openAI))
    }

    func testRefusalIsNotAcceptedAsDraft() async throws {
        StubURLProtocol.handler = { request in
            let response: [String: Any] = [
                "output": [
                    [
                        "type": "message",
                        "content": [["type": "refusal", "refusal": "cannot process source"]],
                    ]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }
        await assertModelError(.refusal(.openAI, "cannot process source"))
    }

    func testMalformedOutputIsRejected() async throws {
        StubURLProtocol.handler = { request in
            let response: [String: Any] = [
                "output": [
                    [
                        "type": "message",
                        "content": [["type": "output_text", "text": "not-json"]],
                    ]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }
        do {
            _ = try await makeClient().generate(
                request: ContextModelRequest(taskID: "task", language: "English", sources: [sourceDocument()]),
                apiKey: "test-key"
            )
            XCTFail("Expected malformed output to be rejected")
        } catch {
            guard case .invalidResponse(.openAI, _) = error as? ContextModelError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUnknownSourceCitationFailsValidation() async throws {
        StubURLProtocol.handler = { request in
            let content = self.validContent(sourceID: "missing-source")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let output = String(data: try encoder.encode(content), encoding: .utf8)!
            let response: [String: Any] = [
                "output": [["type": "message", "content": [["type": "output_text", "text": output]]]]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }
        do {
            _ = try await makeClient().generate(
                request: ContextModelRequest(taskID: "task", language: "English", sources: [sourceDocument()]),
                apiKey: "test-key"
            )
            XCTFail("Expected source validation failure")
        } catch {
            XCTAssertEqual(
                error as? ContextPreparationError,
                .invalidModelOutput("a confirmed claim has missing or unknown sources")
            )
        }
    }

    func testTransportTimeoutIsPropagated() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await makeClient().generate(
                request: ContextModelRequest(taskID: "task", language: "English", sources: [sourceDocument()]),
                apiKey: "test-key"
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testOutputLimitRetriesWithCompactPrompt() async throws {
        let source = sourceDocument()
        StubURLProtocol.handler = { request in
            if StubURLProtocol.requestCount == 1 {
                return try self.incompleteResponse(request: request)
            }
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try self.requestBodyData(request)) as? [String: Any]
            )
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            let systemPrompt = try XCTUnwrap(input.first?["content"] as? String)
            XCTAssertTrue(systemPrompt.contains("compact retry"))
            return try self.successResponse(
                request: request,
                content: self.validContent(sourceID: source.id)
            )
        }

        let result = try await makeClient().generate(
            request: ContextModelRequest(taskID: "task", language: "English", sources: [source]),
            apiKey: "test-key"
        )

        XCTAssertEqual(result.objective, "Objective")
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func testRepeatedOutputLimitFailsAfterCompactRetry() async throws {
        StubURLProtocol.handler = { request in
            try self.incompleteResponse(request: request)
        }

        await assertModelError(.outputTruncated(.openAI))
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func testEmptyAssumptionIsRejected() {
        let source = sourceDocument()
        var content = validContent(sourceID: source.id)
        content.assumptions = [ContextClaim(text: "  ", sourceIDs: [])]

        XCTAssertThrowsError(
            try ContextPreparationService.validated(content, sourceIDs: [source.id])
        ) { error in
            XCTAssertEqual(
                error as? ContextPreparationError,
                .invalidModelOutput("an empty assumption was returned")
            )
        }
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

    private func makeClient() -> OpenAIContextModelClient {
        OpenAIContextModelClient(
            session: stubSession(),
            endpoint: URL(string: "https://example.test/v1/responses")!,
            model: "test-model"
        )
    }

    private func assertModelError(_ expected: ContextModelError) async {
        do {
            _ = try await makeClient().generate(
                request: ContextModelRequest(taskID: "task", language: "English", sources: [sourceDocument()]),
                apiKey: "test-key"
            )
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? ContextModelError, expected)
        }
    }

    private func validContent(sourceID: String) -> ContextPackContent {
        let claim = ContextClaim(text: "Confirmed", sourceIDs: [sourceID])
        return ContextPackContent(
            objective: "Objective", scopeIn: [claim], scopeOut: [], confirmedFacts: [claim],
            constraints: [claim], acceptanceCriteria: [claim], assumptions: [], questions: [],
            brief: "Concise brief", recommendedSourceIDs: [sourceID]
        )
    }

    private func successResponse(
        request: URLRequest,
        content: ContextPackContent
    ) throws -> (HTTPURLResponse, Data) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let output = String(data: try encoder.encode(content), encoding: .utf8)!
        let response: [String: Any] = [
            "output": [["type": "message", "content": [["type": "output_text", "text": output]]]]
        ]
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            try JSONSerialization.data(withJSONObject: response)
        )
    }

    private func incompleteResponse(request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let response: [String: Any] = [
            "status": "incomplete",
            "incomplete_details": ["reason": "max_output_tokens"],
            "output": [],
        ]
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            try JSONSerialization.data(withJSONObject: response)
        )
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
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

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
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
