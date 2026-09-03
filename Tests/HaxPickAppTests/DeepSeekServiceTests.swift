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

    func testCompleteBuildsBearerRequestWithSelectedModelAndFullMessages() async throws {
        let client = MockDeepSeekHTTPClient(
            data: Self.successResponseData(content: "  结果  "),
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .pro },
            httpClient: client
        )
        let messages = [
            AiMessage(role: .system, content: "system", isVisible: false),
            AiMessage(role: .user, content: "Hello", isVisible: false),
            AiMessage(role: .assistant, content: "你好"),
            AiMessage(role: .user, content: "为什么这样翻译？"),
        ]

        let result = try await service.complete(messages: messages)

        XCTAssertEqual(result, "结果")
        XCTAssertEqual(client.recordedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let body = try XCTUnwrap(client.recordedRequest?.httpBody)
        let payload = try Self.jsonObject(from: body)
        XCTAssertEqual(payload["model"] as? String, "deepseek-v4-pro")

        let requestMessages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(requestMessages.count, 4)
        XCTAssertEqual(requestMessages.map { $0["role"] as? String }, ["system", "user", "assistant", "user"])
        XCTAssertEqual(requestMessages[3]["content"] as? String, "为什么这样翻译？")
    }

    func testCompleteMissingAPIKeyDoesNotSendRequest() async {
        let client = MockDeepSeekHTTPClient(
            data: Data(),
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "" },
            modelProvider: { .flash },
            httpClient: client
        )

        do {
            _ = try await service.complete(
                messages: [AiMessage(role: .user, content: "Hello")]
            )
            XCTFail("Expected missingAPIKey error")
        } catch let error as DeepSeekError {
            XCTAssertEqual(error.errorDescription, "请先在菜单栏面板里填写 DeepSeek API Key。")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(client.recordedRequest)
    }

    func testRequestFailed401ScopeMessageIsExplained() {
        let error = DeepSeekError.requestFailed(statusCode: 401, message: "Authentication Fails, Your api key: ****cope is invalid")
        XCTAssertEqual(
            error.errorDescription,
            "DeepSeek 认证失败：API Key 无效或授权不足。请确认你填的是 DeepSeek 平台可用的 Key，并切换模型后重试。"
        )
    }

    private static func successResponseData(content: String) -> Data {
        let body: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": content
                    ]
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/chat/completions")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return try XCTUnwrap(object as? [String: Any])
    }
}

private final class MockDeepSeekHTTPClient: DeepSeekHTTPClient {
    let data: Data
    let response: URLResponse
    private(set) var recordedRequest: URLRequest?

    init(data: Data, response: URLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequest = request
        return (data, response)
    }
}
