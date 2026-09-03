enum AiPrompts {
    private static let paragraphInstruction = "每个句子请用句号结尾并换行以形成自然段落；简短连续的内容请用逗号连接，不要强行断句。"

    static func systemPrompt(for action: AiToolAction) -> String {
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

        return basePrompt + " 后续用户消息都视为当前任务的继续提问，请结合原文和完整对话历史回答。" + paragraphInstruction
    }

    static func initialUserPrompt(for action: AiToolAction, text: String) -> String {
        let prompt: String
        switch action {
        case .translate:
            prompt = """
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
            prompt = """
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
            prompt = """
            请总结下面内容。使用 Markdown 语法格式化输出，代码块用三个反引号包裹并标注语言。

            输出结构：
            1. 一句话总结
            2. 2 到 4 条重点 bullet

            原文：
            \(text)
            """
        case .polish:
            prompt = """
            请润色下面内容，让表达更自然、清晰、简洁。使用 Markdown 语法格式化输出。

            原文：
            \(text)
            """
        case .rewrite:
            prompt = """
            请在不改变原意的前提下改写下面内容，给出更流畅的一版表达。使用 Markdown 语法格式化输出，代码块用三个反引号包裹并标注语言。

            原文：
            \(text)
            """
        case .extract:
            prompt = """
            请从下面内容中提取要点。使用 Markdown 语法格式化输出，代码块用三个反引号包裹并标注语言。

            输出结构：
            1. 一句话概述
            2. 3 到 5 条要点

            原文：
            \(text)
            """
        case .copy:
            prompt = text
        }

        return prompt + "\n\n" + paragraphInstruction
    }
}
