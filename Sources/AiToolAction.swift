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

}
