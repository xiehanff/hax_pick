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
            switch self {
            case .flash:
                return "deepseek-v4-flash"
            case .pro:
                return "deepseek-v4-pro"
            }
        }
    }

    enum ToolAction: String, CaseIterable, Identifiable {
        case copy = "复制"
        case translate = "翻译"
        case explain = "解释"
        case summarize = "总结"
        case polish = "润色"
        case rewrite = "改写"
        case extract = "提取要点"

        var id: String { rawValue }

        static let primaryActions: [ToolAction] = [.copy, .translate, .explain, .summarize]

        var symbolName: String {
            switch self {
            case .copy:
                return "doc.on.doc"
            case .translate:
                return "globe"
            case .explain:
                return "text.bubble"
            case .summarize:
                return "list.bullet.rectangle"
            case .polish:
                return "wand.and.stars"
            case .rewrite:
                return "arrow.triangle.2.circlepath"
            case .extract:
                return "line.3.horizontal.decrease.circle"
            }
        }

        var resultTitle: String {
            switch self {
            case .copy:
                return "这里是原文"
            case .translate:
                return "这里是我的翻译"
            case .explain:
                return "这里是我的解释"
            case .summarize:
                return "这里是我的总结"
            case .polish:
                return "这里是我的润色"
            case .rewrite:
                return "这里是我的改写"
            case .extract:
                return "这里是我的提取要点"
            }
        }

        var contentTitle: String {
            switch self {
            case .translate:
                return "翻译结果"
            case .explain:
                return "解释结果"
            case .summarize:
                return "总结结果"
            case .polish:
                return "润色结果"
            case .rewrite:
                return "改写结果"
            case .extract:
                return "要点结果"
            case .copy:
                return "结果"
            }
        }

        var suggestions: [String] {
            switch self {
            case .translate:
                return ["这句话为什么这样翻译？", "换一个更自然的说法", "给我一个例句"]
            case .explain:
                return ["用更简单的话解释", "给我一个例子", "这背后的背景是什么？"]
            case .summarize:
                return ["提炼成 3 个要点", "给我一个更短版本", "哪些信息最重要？"]
            case .polish:
                return ["更正式一点", "更口语一点", "保留原意再简洁些"]
            case .rewrite:
                return ["换一种表达方式", "适合邮件场景", "适合口语场景"]
            case .extract:
                return ["按 bullet 再整理", "只保留结论", "提取可执行事项"]
            case .copy:
                return []
            }
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

    func perform(
        action: ToolAction,
        text: String,
        previousResult: String? = nil,
        followUp: String? = nil
    ) async throws -> String {
        let apiKey = apiKeyProvider()
        guard !apiKey.isEmpty else {
            throw DeepSeekError.missingAPIKey
        }

        let userPrompt = buildPrompt(
            action: action,
            text: text,
            previousResult: previousResult,
            followUp: followUp
        )
        let model = modelProvider()
        let requestBody = ChatRequest(
            model: model.rawValue,
            messages: [
                .init(role: "system", content: systemPrompt(for: action)),
                .init(role: "user", content: userPrompt),
            ]
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
            throw DeepSeekError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw DeepSeekError.emptyResult
        }
        return content
    }

    private func systemPrompt(for action: ToolAction) -> String {
        let basePrompt: String
        switch action {
        case .translate:
            basePrompt = "你是一个翻译助手。输出必须使用 Markdown 语法，简洁、自然、结构化，适合在桌面小面板中阅读。代码片段请用三个反引号包裹并标注语言。"
        case .explain:
            basePrompt = "你是一个解释助手。输出必须使用 Markdown 语法，先给简要解释，再用分点说明，必要时补充背景。代码片段请用三个反引号包裹并标注语言。"
        case .summarize, .extract:
            basePrompt = "你是一个总结助手。输出必须使用 Markdown 语法，先给一句总述，再用 2-4 条要点简明总结。代码片段请用三个反引号包裹并标注语言。"
        case .polish:
            basePrompt = "你是一个中文润色助手。请在不改变原意的前提下优化表达，输出直接可用。使用 Markdown 语法格式化，代码片段请用三个反引号包裹并标注语言。"
        case .rewrite:
            basePrompt = "你是一个改写助手。请根据原文进行不同表达方式的改写，保持自然、清晰。使用 Markdown 语法格式化，代码片段请用三个反引号包裹并标注语言。"
        case .copy:
            basePrompt = "你是一个简洁、准确的语言助手。使用 Markdown 语法格式化输出，代码片段请用三个反引号包裹并标注语言。"
        }
        return basePrompt + " 每个句子请用句号结尾并换行以形成自然段落；简短连续的内容请用逗号连接，不要强行断句。"
    }

    private func buildPrompt(
        action: ToolAction,
        text: String,
        previousResult: String?,
        followUp: String?
    ) -> String {
        if let followUp, !followUp.isEmpty {
            return """
            当前原文：
            \(text)

            上一轮结果：
            \(previousResult ?? "无")

            用户继续提问：
            \(followUp)

            请基于当前任务类型继续回答，使用 Markdown 语法，保持结构化、简洁，适合桌面悬浮面板阅读。代码块用三个反引号包裹并标注语言。每个句子请用句号结尾并换行；简短连续的内容请用逗号连接。
            """
        }

        switch action {
        case .translate:
            return """
            请将下面内容翻译成简体中文，并保留原意。使用 Markdown 语法格式化输出。代码块用三个反引号包裹并标注语言。

            如果是单词或短语，请按以下结构输出：
            主要译文
            词性/音标
            常见搭配
            例句

            如果是句子或段落，请优先给自然中文，不要逐词硬译。

            原文：
            \(text)
            """
        case .explain:
            return """
            请用简洁中文解释下面内容。使用 Markdown 语法格式化输出，代码块用三个反引号包裹并标注语言。

            输出结构：
            1. 简要解释
            2. 分点解析
            3. 必要背景补充
            4. 一句话总结

            原文：
            \(text)
            """
        case .summarize:
            return """
            请总结下面内容。使用 Markdown 语法格式化输出，代码块用三个反引号包裹并标注语言。

            输出结构：
            1. 一句话总结
            2. 2 到 4 条重点 bullet

            原文：
            \(text)
            """
        case .polish:
            return """
            请润色下面内容，让表达更自然、清晰、简洁。使用 Markdown 语法格式化输出。

            原文：
            \(text)
            """
        case .rewrite:
            return """
            请在不改变原意的前提下改写下面内容，给出更流畅的一版表达。使用 Markdown 语法格式化输出，代码块用三个反引号包裹并标注语言。

            原文：
            \(text)
            """
        case .extract:
            return """
            请从下面内容中提取要点。使用 Markdown 语法格式化输出，代码块用三个反引号包裹并标注语言。

            输出结构：
            1. 一句话概述
            2. 3 到 5 条要点

            原文：
            \(text)
            """
        case .copy:
            return text
        }
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
                if lowercased.contains("authentication fails") || lowercased.contains("api key") || lowercased.contains("invalid") {
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
