import Foundation

enum AiMessageRole: String, Codable {
    case system
    case user
    case assistant
}

struct AiMessage: Identifiable, Equatable {
    let id: UUID
    let role: AiMessageRole
    let content: String
    let isVisible: Bool

    init(
        id: UUID = UUID(),
        role: AiMessageRole,
        content: String,
        isVisible: Bool = true
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isVisible = isVisible
    }
}
