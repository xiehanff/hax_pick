import Foundation

enum AiToolAction: String, CaseIterable, Identifiable {
    case copy = "复制"
    case translate = "翻译"
    case explain = "解释"
    case summarize = "总结"
    case polish = "润色"
    case rewrite = "改写"
    case extract = "提取要点"

    var id: String { rawValue }

    /// MVP 只在划词工具条暴露翻译和解释；复制作为独立的基础操作展示。
    static let primaryActions: [AiToolAction] = [.translate, .explain]

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
            return "翻译"
        case .explain:
            return "解释"
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
