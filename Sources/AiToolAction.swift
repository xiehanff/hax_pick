import Foundation

enum AiToolAction: String, CaseIterable, Identifiable {
    case copy = "复制"
    case translate = "翻译"
    case explain = "解释"
    case deepDive = "深度理解"
    case chat = "随便聊"
    case summarize = "总结"
    case polish = "润色"
    case rewrite = "改写"
    case extract = "提取要点"

    var id: String { rawValue }

    /// 当前划词工具条暴露翻译、解释、深度理解和自由问答；复制作为独立基础操作展示。
    static let primaryActions: [AiToolAction] = [.translate, .explain, .deepDive, .chat]

    var symbolName: String {
        switch self {
        case .copy:
            return "doc.on.doc"
        case .translate:
            return "globe"
        case .explain:
            return "text.bubble"
        case .deepDive:
            return "brain.head.profile"
        case .chat:
            return "bubble.left.and.bubble.right"
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
            return "原文"
        case .translate:
            return "翻译"
        case .explain:
            return "解释"
        case .deepDive:
            return "深度理解"
        case .chat:
            return "随便聊"
        case .summarize:
            return "总结"
        case .polish:
            return "润色"
        case .rewrite:
            return "改写"
        case .extract:
            return "提取要点"
        }
    }

    var contentTitle: String {
        switch self {
        case .translate:
            return "翻译结果"
        case .explain:
            return "解释结果"
        case .deepDive:
            return "深度理解"
        case .chat:
            return "回答"
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
}
