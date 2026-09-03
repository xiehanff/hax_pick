import Foundation

protocol DeepSeekStreamingHTTPClient {
    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse)
}

extension URLSession: DeepSeekStreamingHTTPClient {
    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        let (bytes, response) = try await bytes(for: request)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return (stream, response)
    }
}

struct DeepSeekService {
    enum Model: String, CaseIterable, Identifiable {
        case flash = "deepseek-v4-flash"
        case pro = "deepseek-v4-pro"

        var id: String { rawValue }

        var displayName: String {
            rawValue
        }
    }

    private let apiKeyProvider: () -> String
    private let modelProvider: () -> Model
    private let streamingClient: any DeepSeekStreamingHTTPClient

    init(
        apiKeyProvider: @escaping () -> String,
        modelProvider: @escaping () -> Model,
        streamingClient: any DeepSeekStreamingHTTPClient = URLSession.shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider
        self.streamingClient = streamingClient
    }

    func stream(messages: [AiMessage]) -> AsyncThrowingStream<String, Error> {
        let apiKey = apiKeyProvider()
        let model = modelProvider()
        let streamingClient = streamingClient

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else {
                        throw DeepSeekError.missingAPIKey
                    }

                    let request = try makeRequest(
                        apiKey: apiKey,
                        model: model,
                        messages: messages
                    )
                    let (lines, response) = try await streamingClient.lines(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw DeepSeekError.invalidResponse
                    }

                    guard 200..<300 ~= httpResponse.statusCode else {
                        var bodyLines: [String] = []
                        for try await line in lines {
                            bodyLines.append(line)
                        }
                        let body = bodyLines.joined(separator: "\n")
                        let data = Data(body.utf8)
                        let message = APIErrorMessageParser.message(from: data)
                        throw DeepSeekError.requestFailed(
                            statusCode: httpResponse.statusCode,
                            message: message
                        )
                    }

                    var emittedContent = false
                    for try await line in lines {
                        try Task.checkCancellation()
                        guard let payload = Self.ssePayload(from: line) else {
                            continue
                        }
                        if payload == "[DONE]" {
                            break
                        }

                        guard let data = payload.data(using: .utf8) else {
                            continue
                        }
                        let decoded = try JSONDecoder().decode(StreamResponse.self, from: data)
                        for choice in decoded.choices {
                            guard let content = choice.delta.content, !content.isEmpty else {
                                continue
                            }
                            emittedContent = true
                            continuation.yield(content)
                        }
                    }

                    guard emittedContent else {
                        throw DeepSeekError.emptyResult
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func complete(messages: [AiMessage]) async throws -> String {
        var output = ""
        for try await chunk in stream(messages: messages) {
            output += chunk
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DeepSeekError.emptyResult
        }
        return trimmed
    }

    private func makeRequest(
        apiKey: String,
        model: Model,
        messages: [AiMessage]
    ) throws -> URLRequest {
        let requestBody = ChatRequest(
            model: model.rawValue,
            messages: messages.map {
                ChatMessage(role: $0.role.rawValue, content: $0.content)
            },
            stream: true
        )

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 45
        return request
    }

    private static func ssePayload(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return String(line.dropFirst(5))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum APIErrorMessageParser {
    static func message(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            let message = payload.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                return message
            }
        }
        return String(data: data, encoding: .utf8) ?? "未知错误"
    }
}

enum DeepSeekError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyResult
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在菜单栏面板里填写 DeepSeek API Key。"
        case .invalidResponse:
            return "DeepSeek 响应格式无效。"
        case .emptyResult:
            return "DeepSeek 没有返回可展示的内容。"
        case .requestFailed(let statusCode, let message):
            if statusCode == 401 || statusCode == 403 {
                let lowercased = message.lowercased()
                if lowercased.contains("model") {
                    return "DeepSeek 认证失败：当前 Key 没有这个模型的权限。请切换模型后重试，或换一个有权限的 Key。"
                }
                if lowercased.contains("authentication fails") ||
                    lowercased.contains("api key") ||
                    lowercased.contains("invalid") {
                    return "DeepSeek 认证失败：API Key 无效或授权不足。请确认你填的是 DeepSeek 平台可用的 Key，并切换模型后重试。"
                }
                return "DeepSeek 认证失败：\(message)"
            }
            if statusCode == 400 || statusCode == 422 {
                let lowercased = message.lowercased()
                if lowercased.contains("model") {
                    return "当前模型不可用，请在菜单栏里切换模型后重试。"
                }
            }
            return "DeepSeek 请求失败：\(message)"
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct StreamResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private struct ErrorPayload: Decodable {
    let error: ErrorItem

    struct ErrorItem: Decodable {
        let message: String
    }
}
