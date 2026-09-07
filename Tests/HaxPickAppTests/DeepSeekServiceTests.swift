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

        var chunks: [AiStreamChunk] = []
        for try await chunk in service.stream(messages: messages) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks.map(\.content), ["你", "好"])
        XCTAssertTrue(chunks.allSatisfy { $0.reasoning.isEmpty })
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

    func testStreamYieldsReasoningAndAnswerAsIndependentChannels() async throws {
        let client = MockDeepSeekStreamingHTTPClient(
            lines: [
                "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"先分析语境\"}}]}",
                "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"，再组织答案\"}}]}",
                "data: {\"choices\":[{\"delta\":{\"content\":\"最终答案\"}}]}",
                "data: [DONE]",
            ],
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .flash },
            streamingClient: client
        )

        var reasoning = ""
        var content = ""
        for try await chunk in service.stream(
            messages: [AiMessage(role: .user, content: "解释一下")],
            mode: .lowReasoning
        ) {
            reasoning += chunk.reasoning
            content += chunk.content
        }

        XCTAssertEqual(reasoning, "先分析语境，再组织答案")
        XCTAssertEqual(content, "最终答案")
    }

    func testTranslationDisablesThinkingAndExplainUsesLowReasoning() async throws {
        let translationClient = MockDeepSeekStreamingHTTPClient(
            lines: [
                "data: {\"choices\":[{\"delta\":{\"content\":\"好\"}}]}",
                "data: [DONE]",
            ],
            response: Self.httpResponse(statusCode: 200)
        )
        let translationService = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .flash },
            streamingClient: translationClient
        )
        for try await _ in translationService.stream(
            messages: [AiMessage(role: .user, content: "hello")],
            mode: .translation
        ) {}

        let translationBody = try XCTUnwrap(translationClient.recordedRequest?.httpBody)
        let translationPayload = try Self.jsonObject(from: translationBody)
        XCTAssertEqual(
            (translationPayload["thinking"] as? [String: Any])?["type"] as? String,
            "disabled"
        )
        XCTAssertNil(translationPayload["reasoning_effort"])

        let explainClient = MockDeepSeekStreamingHTTPClient(
            lines: [
                "data: {\"choices\":[{\"delta\":{\"content\":\"解释\"}}]}",
                "data: [DONE]",
            ],
            response: Self.httpResponse(statusCode: 200)
        )
        let explainService = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .flash },
            streamingClient: explainClient
        )
        for try await _ in explainService.stream(
            messages: [AiMessage(role: .user, content: "hello")],
            mode: .lowReasoning
        ) {}

        let explainBody = try XCTUnwrap(explainClient.recordedRequest?.httpBody)
        let explainPayload = try Self.jsonObject(from: explainBody)
        XCTAssertEqual(
            (explainPayload["thinking"] as? [String: Any])?["type"] as? String,
            "enabled"
        )
        XCTAssertEqual(explainPayload["reasoning_effort"] as? String, "low")
    }

    func testStreamIgnoresKeepAliveCommentsAndBlankLines() async throws {
        let client = MockDeepSeekStreamingHTTPClient(
            lines: [
                ": keep-alive",
                "",
                "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}",
                ": keep-alive",
                "data: [DONE]",
            ],
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .flash },
            streamingClient: client
        )

        var chunks: [AiStreamChunk] = []
        for try await chunk in service.stream(
            messages: [AiMessage(role: .user, content: "Hello")]
        ) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks.map(\.content), ["ok"])
    }

    func testStreamRejectsEOFBeforeDoneAfterPartialContent() async {
        let client = MockDeepSeekStreamingHTTPClient(
            lines: [
                "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}",
            ],
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .flash },
            streamingClient: client
        )

        var chunks: [AiStreamChunk] = []
        do {
            for try await chunk in service.stream(
                messages: [AiMessage(role: .user, content: "Hello")]
            ) {
                chunks.append(chunk)
            }
            XCTFail("Expected incompleteStream error")
        } catch let error as DeepSeekError {
            XCTAssertEqual(
                error.errorDescription,
                "DeepSeek 流式响应提前中断，回答可能不完整，请重试。"
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(chunks.map(\.content), ["partial"])
    }

    func testCompleteAggregatesStreamedChunksAndHidesSuggestionProtocol() async throws {
        let client = MockDeepSeekStreamingHTTPClient(
            lines: [
                "data: {\"choices\":[{\"delta\":{\"content\":\" 结果\"}}]}",
                "data: {\"choices\":[{\"delta\":{\"content\":\"\\n<hax_follow_up_suggestions>\\n[\\\"继续解释\\\"]\\n</hax_follow_up_suggestions>\"}}]}",
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

    func testResponseParserExtractsContextualSuggestions() {
        let raw = """
        这里是正文。
        <hax_follow_up_suggestions>
        ["为什么会这样？", "给我一个具体例子", "和另一种做法有什么区别？"]
        </hax_follow_up_suggestions>
        """

        let response = AiResponseParser.parse(raw)

        XCTAssertEqual(response.content, "这里是正文。")
        XCTAssertEqual(
            response.followUpSuggestions,
            ["为什么会这样？", "给我一个具体例子", "和另一种做法有什么区别？"]
        )
    }

    func testResponseParserHidesIncompleteSuggestionTagDuringStreaming() {
        let partial = "正文已经完成。\n<hax_follow_up_sugges"
        let response = AiResponseParser.parse(partial)

        XCTAssertEqual(response.content, "正文已经完成。")
        XCTAssertTrue(response.followUpSuggestions.isEmpty)
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
