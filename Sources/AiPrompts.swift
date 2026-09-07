import Foundation

struct AiResponse: Equatable {
    let content: String
    let followUpSuggestions: [String]
}

enum AiResponseParser {
    static let suggestionsStartTag = "<hax_follow_up_suggestions>"
    static let suggestionsEndTag = "</hax_follow_up_suggestions>"

    static let followUpInstruction = """
    回答正文完成后，必须根据本轮问题、回答内容、原文和已有对话历史，生成 2-4 个自然且具体的后续提问或操作建议。建议必须与当前上下文相关，不要使用固定模板，不要重复用户已经提出的问题，每条尽量简短。建议不要混入回答正文，必须严格放在以下标记中，标记内容只允许是 JSON 字符串数组：
    \(suggestionsStartTag)
    ["建议一", "建议二", "建议三"]
    \(suggestionsEndTag)
    """

    static func parse(_ raw: String) -> AiResponse {
        guard let startRange = raw.range(of: suggestionsStartTag) else {
            return AiResponse(
                content: removeIncompleteStartTag(from: raw),
                followUpSuggestions: []
            )
        }

        let content = String(raw[..<startRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestionsStart = startRange.upperBound
        guard let endRange = raw.range(
            of: suggestionsEndTag,
            range: suggestionsStart..<raw.endIndex
        ) else {
            return AiResponse(content: content, followUpSuggestions: [])
        }

        let payload = String(raw[suggestionsStart..<endRange.lowerBound])
        return AiResponse(
            content: content,
            followUpSuggestions: parseSuggestions(payload)
        )
    }

    private static func removeIncompleteStartTag(from raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let minimumPrefixLength = min(8, suggestionsStartTag.count)
        if suggestionsStartTag.count > minimumPrefixLength {
            for length in stride(
                from: suggestionsStartTag.count - 1,
                through: minimumPrefixLength,
                by: -1
            ) {
                let partial = String(suggestionsStartTag.prefix(length))
                if raw.hasSuffix(partial) {
                    return String(raw.dropLast(partial.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseSuggestions(_ raw: String) -> [String] {
        let candidate = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^```(?:json)?\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s*```$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = candidate.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data) {
            if let values = value as? [Any] {
                return normalizeSuggestions(values)
            }
            if let object = value as? [String: Any],
               let values = object["suggestions"] as? [Any] {
                return normalizeSuggestions(values)
            }
        }

        return normalizeSuggestions(candidate.components(separatedBy: .newlines))
    }

    private static func normalizeSuggestions(_ values: [Any]) -> [String] {
        var output: [String] = []
        for value in values {
            let raw = (value as? String) ?? String(describing: value)
            let normalized = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(
                    of: #"^(?:[-*•]|\d+[.)])\s+"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !output.contains(normalized) else { continue }
            output.append(normalized)
            if output.count == 4 { break }
        }
        return output
    }
}

enum AiPrompts {
    private static let paragraphInstruction = "每个句子请用句号结尾并自然分段；简短连续的内容不要为了形式强行断句。"

    static func systemPrompt(for action: AiToolAction) -> String {
        let basePrompt: String
        switch action {
        case .translate:
            basePrompt = "你是一个专业翻译。原文主要是中文时译为自然英文，主要是其他语言时译为简体中文。先输出译文本身，然后另起一行输出“**总结**：”，用简体中文用 1-2 句话概括主要内容。不要复述原文，不要解释翻译过程。使用清晰的 Markdown。"
        case .explain:
            basePrompt = "你是一个解释助手。请使用简体中文和清晰的 Markdown，先给简要解释，再按需要分点展开并补充必要背景。直接回答内容本身，不要复述问题或提及输入形式。"
        case .deepDive:
            basePrompt = """
            你是一位严谨、耐心的讲师。把用户当作对当前主题几乎没有背景知识的新手，输出一篇结构完整、内容深入的 Markdown 长文讲解。请充分思考后再组织答案，篇幅可以较长（通常 1000 字以上），但不要为了凑字数重复。
            严格遵循以下教学规则：
            1. 从一个能体现该知识点价值的真实问题、经典问题或实际困惑切入，先说明现有做法的痛点；简单主题无需刻意编造复杂场景。
            2. 依次讲清“为什么需要 → 它是什么 → 如何工作 → 最小示例”，再逐步增加示例复杂度。
            3. 明确它解决的问题类型、适用前提、优点、缺点和失败边界；不要默认它在所有场景都是最优方案。
            4. 与容易混淆或可替代的概念做对比，说明选择标准，并为关键差异提供具体例子。
            5. 概念建立后再扩展到其他应用场景；如果存在更合适的方案，要说明为什么以及什么时候替换。
            6. 涉及 API、术语或实现细节时，只讲与当前主题和示例直接相关的部分；不要无意义罗列参考手册。
            7. 区分确定事实、常见经验和推断；遇到输入信息不足时明确说明边界，不要编造不存在的细节。
            """
        case .summarize, .extract:
            basePrompt = "你是一个总结助手。请使用简体中文和清晰的 Markdown，先给一句总述，再提炼最重要的信息。不要为了凑结构重复内容。"
        case .polish:
            basePrompt = "你是一个中文润色助手。请在不改变原意的前提下优化表达，输出可以直接使用的版本。"
        case .rewrite:
            basePrompt = "你是一个改写助手。请保持原意，换成更自然、清晰的表达。"
        case .copy:
            basePrompt = "你是一个简洁、准确的语言助手。"
        }

        return basePrompt
            + " 后续用户消息都视为当前任务的继续提问，请结合原文和完整对话历史回答。 "
            + paragraphInstruction
            + "\n\n"
            + AiResponseParser.followUpInstruction
    }

    static func initialUserPrompt(for action: AiToolAction, text: String) -> String {
        let prompt: String
        switch action {
        case .translate:
            prompt = "请翻译下面内容，保持原意和语气：\n\n\(text)"
        case .explain:
            prompt = "请用简洁中文解释下面内容，并补充理解它所需的必要背景：\n\n\(text)"
        case .deepDive:
            prompt = "请以零基础新手的视角，深入讲解下面内容。用通俗语言、具体例子和必要对比，按既定教学规则把概念真正讲透：\n\n\(text)"
        case .summarize:
            prompt = "请总结下面内容，先给一句总述，再列出最重要的要点：\n\n\(text)"
        case .polish:
            prompt = "请润色下面内容，让表达更自然、清晰、简洁：\n\n\(text)"
        case .rewrite:
            prompt = "请在不改变原意的前提下改写下面内容：\n\n\(text)"
        case .extract:
            prompt = "请从下面内容中提取真正重要的信息和可执行事项：\n\n\(text)"
        case .copy:
            prompt = text
        }

        return prompt + "\n\n" + paragraphInstruction
    }
}
