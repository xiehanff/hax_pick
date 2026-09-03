import Foundation

protocol DeepSeekHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: DeepSeekHTTPClient {}

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
    private let httpClient: any DeepSeekHTTPClient

    init(
        apiKeyProvider: @escaping () -> String,
        modelProvider: @escaping () -> Model,
        httpClient: any DeepSeekHTTPClient = URLSession.shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider
        self.httpClient = httpClient
    }

    func complete(messages: [AiMessage]) async throws -> String {
        let apiKey = apiKeyProvider()
        guard !apiKey.isEmpty else {
            throw DeepSeekError.missingAPIKey
        }

        let model = modelProvider()
        let requestBody = ChatRequest(
            model: model.rawValue,
            messages: messages.map {
                ChatMessage(role: $0.role.rawValue, content: $0.content)
            }
        )

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 45

        let (data, response) = try await httpClient.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = APIErrorMessageParser.message(from: data)
            throw DeepSeekError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw DeepSeekError.emptyResult
        }
        return content
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
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct ErrorPayload: Decodable {
    let error: ErrorItem

    struct ErrorItem: Decodable {
        let message: String
    }
}
