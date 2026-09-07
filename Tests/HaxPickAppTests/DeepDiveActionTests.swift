import Foundation
import XCTest
@testable import HaxPickApp

@MainActor
final class DeepDiveActionTests: XCTestCase {
    func testDeepDivePromptUsesStructuredZeroBackgroundTeachingFlow() {
        let systemPrompt = AiPrompts.systemPrompt(for: .deepDive)
        let userPrompt = AiPrompts.initialUserPrompt(for: .deepDive, text: "MVCC")

        XCTAssertTrue(systemPrompt.contains("为什么需要"))
        XCTAssertTrue(systemPrompt.contains("如何工作"))
        XCTAssertTrue(systemPrompt.contains("失败边界"))
        XCTAssertTrue(systemPrompt.contains("1000 字以上"))
        XCTAssertTrue(systemPrompt.contains(AiResponseParser.suggestionsStartTag))
        XCTAssertTrue(userPrompt.contains("零基础新手"))
        XCTAssertTrue(userPrompt.contains("MVCC"))
    }

    func testDeepDiveRequestEnablesFullThinkingAndLargeOutputBudget() async throws {
        let client = DeepDiveMockClient(
            lines: [
                "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"先分析\"}}]}",
                "data: {\"choices\":[{\"delta\":{\"content\":\"深入回答\"}}]}",
                "data: [DONE]",
            ],
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .pro },
            streamingClient: client
        )

        var reasoning = ""
        var content = ""
        for try await chunk in service.stream(
            messages: [AiMessage(role: .user, content: "MVCC")],
            mode: .deepDive
        ) {
            reasoning += chunk.reasoning
            content += chunk.content
        }

        XCTAssertEqual(reasoning, "先分析")
        XCTAssertEqual(content, "深入回答")

        let body = try XCTUnwrap(client.recordedRequest?.httpBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let payload = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(
            (payload["thinking"] as? [String: Any])?["type"] as? String,
            "enabled"
        )
        XCTAssertNil(payload["reasoning_effort"])
        XCTAssertEqual(payload["max_tokens"] as? Int, 32768)
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/chat/completions")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
    }
}

private final class DeepDiveMockClient: DeepSeekStreamingHTTPClient {
    let lines: [String]
    let response: URLResponse
    private(set) var recordedRequest: URLRequest?

    init(lines: [String], response: URLResponse) {
        self.lines = lines
        self.response = response
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        recordedRequest = request
        let values = lines
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in values {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return (stream, response)
    }
}
