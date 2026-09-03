import Foundation
import XCTest
@testable import HaxPickApp

@MainActor
final class DeepSeekServiceTests: XCTestCase {
    func testNormalizedAPIKeyReturnsEmptyForInvalidStoredValue() {
        XCTAssertEqual(
            AppState.normalizedAPIKey(from: "  not-a-deepseek-key  "),
            ""
        )
    }

    func testPersistableAPIKeyIgnoresEmptyValue() {
        XCTAssertNil(AppState.persistableAPIKey(from: "   "))
        XCTAssertEqual(AppState.persistableAPIKey(from: "  sk-test  "), "sk-test")
    }

    func testStreamBuildsBearerRequestAndYieldsSSEChunks() async throws {
        let client = MockDeepSeekStreamingHTTPClient(
            lines: [
                "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}",
                "data: {\"choices\":[{\"delta\":{\"content\":\"好\"}}]}",
                "data: [DONE]",
            ],
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .pro },
            streamingClient: client
        )
        let messages = [
            AiMessage(role: .system, content: "system", isVisible: false),
            AiMessage(role: .user, content: "Hello", isVisible: false),
            AiMessage(role: .assistant, content: "你好"),
            AiMessage(role: .user, content: "为什么这样翻译？"),
        ]

        var chunks: [String] = []
        for try await chunk in service.stream(messages: messages) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks, ["你", "好"])
        XCTAssertEqual(client.recordedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let body = try XCTUnwrap(client.recordedRequest?.httpBody)
        let payload = try Self.jsonObject(from: body)
        XCTAssertEqual(payload["model"] as? String, "deepseek-v4-pro")
        XCTAssertEqual(payload["stream"] as? Bool, true)

        let requestMessages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(requestMessages.count, 4)
        XCTAssertEqual(requestMessages.map { $0["role"] as? String }, ["system", "user", "assistant", "user"])
        XCTAssertEqual(requestMessages[3]["content"] as? String, "为什么这样翻译？")
    }

    func testCompleteAggregatesStreamedChunks() async throws {
        let client = MockDeepSeekStreamingHTTPClient(
            lines: [
                "data: {\"choices\":[{\"delta\":{\"content\":\" 结\"}}]}",
                "data: {\"choices\":[{\"delta\":{\"content\":\"果 \"}}]}",
                "data: [DONE]",
            ],
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .flash },
            streamingClient: client
        )

        let result = try await service.complete(
            messages: [AiMessage(role: .user, content: "Hello")]
        )

        XCTAssertEqual(result, "结果")
    }

    func testStreamMissingAPIKeyDoesNotSendRequest() async {
        let client = MockDeepSeekStreamingHTTPClient(
            lines: [],
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "" },
            modelProvider: { .flash },
            streamingClient: client
        )

        do {
            for try await _ in service.stream(
                messages: [AiMessage(role: .user, content: "Hello")]
            ) {}
            XCTFail("Expected missingAPIKey error")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error.errorDescription, "请先在菜单栏面板里填写 DeepSeek API Key。")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(client.recordedRequest)
    }

    func testStreamMapsHTTPErrorBody() async {
        let client = MockDeepSeekStreamingHTTPClient(
            lines: ["{\"error\":{\"message\":\"Authentication Fails, api key invalid\"}}"],
            response: Self.httpResponse(statusCode: 401)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "bad-key" },
            modelProvider: { .flash },
            streamingClient: client
        )

        do {
            for try await _ in service.stream(
                messages: [AiMessage(role: .user, content: "Hello")]
            ) {}
            XCTFail("Expected requestFailed error")
        } catch let error as DeepSeekError {
            XCTAssertEqual(
                error.errorDescription,
                "DeepSeek 认证失败：API Key 无效或授权不足。请确认你填的是 DeepSeek 平台可用的 Key，并切换模型后重试。"
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestFailed401ScopeMessageIsExplained() {
        let error = DeepSeekError.requestFailed(statusCode: 401, message: "Authentication Fails, Your api key: ****cope is invalid")
        XCTAssertEqual(
            error.errorDescription,
            "DeepSeek 认证失败：API Key 无效或授权不足。请确认你填的是 DeepSeek 平台可用的 Key，并切换模型后重试。"
        )
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/chat/completions")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return try XCTUnwrap(object as? [String: Any])
    }
}

private final class MockDeepSeekStreamingHTTPClient: DeepSeekStreamingHTTPClient {
    let lineValues: [String]
    let response: URLResponse
    private(set) var recordedRequest: URLRequest?

    init(lines: [String], response: URLResponse) {
        self.lineValues = lines
        self.response = response
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        recordedRequest = request
        let values = lineValues
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in values {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return (stream, response)
    }
}
