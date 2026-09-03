import Foundation
import XCTest
@testable import HaxPickApp

@MainActor
final class AiAgentHistoryWindowIntegrationTests: XCTestCase {
    func testServiceBackedSessionWindowsTransportSnapshotWithoutTruncatingLocalHistory() async throws {
        let client = SequencedStreamingHTTPClient(contents: ["A0", "A1", "A2"])
        let service = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .flash },
            streamingClient: client
        )
        let session = AiAgentSession(
            service: service,
            historyWindow: AiHistoryWindow(maxContentCharacters: 32)
        )

        session.runToolAction(.explain, sourceText: "source")
        try await waitForCompletedAssistant(session, content: "A0")

        let q1 = String(repeating: "Q", count: 20)
        XCTAssertTrue(session.sendMessage(q1))
        try await waitForCompletedAssistant(session, content: "A1")

        XCTAssertTrue(session.sendMessage("why?"))
        try await waitForCompletedAssistant(session, content: "A2")

        XCTAssertEqual(session.visibleMessages.map(\.content), ["A0", q1, "A1", "why?", "A2"])
        XCTAssertEqual(client.recordedRequests.count, 3)

        let body = try XCTUnwrap(client.recordedRequests.last?.httpBody)
        let object = try JSONSerialization.jsonObject(with: body)
        let payload = try XCTUnwrap(object as? [String: Any])
        let requestMessages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let contents = requestMessages.compactMap { $0["content"] as? String }

        XCTAssertEqual(requestMessages.count, 5)
        XCTAssertFalse(contents.contains("A0"))
        XCTAssertTrue(contents.contains(q1))
        XCTAssertTrue(contents.contains("A1"))
        XCTAssertEqual(contents.last, "why?")
    }

    private func waitForCompletedAssistant(_ session: AiAgentSession, content: String) async throws {
        for _ in 0..<800 {
            if !session.isLoading && session.lastAssistantContent == content {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected assistant response \(content)")
        throw IntegrationTestError.conditionNotMet
    }
}

private enum IntegrationTestError: Error {
    case conditionNotMet
}

private final class SequencedStreamingHTTPClient: DeepSeekStreamingHTTPClient {
    private var contents: [String]
    private(set) var recordedRequests: [URLRequest] = []

    init(contents: [String]) {
        self.contents = contents
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        recordedRequests.append(request)
        let content = contents.isEmpty ? "fallback" : contents.removeFirst()
        let escaped = try JSONSerialization.data(
            withJSONObject: ["choices": [["delta": ["content": content]]]]
        )
        let payload = String(data: escaped, encoding: .utf8)!
        let lines = ["data: \(payload)", "data: [DONE]"]
        let stream = AsyncThrowingStream<String, Error> { continuation in
            lines.forEach { continuation.yield($0) }
            continuation.finish()
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        return (stream, response)
    }
}
