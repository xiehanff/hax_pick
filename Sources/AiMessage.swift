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

/// Shapes only the model request snapshot. Local conversation history remains intact.
///
/// The budget is intentionally expressed in characters rather than pretending to be
/// an exact tokenizer count. The hidden anchors and newest dependency unit are
/// mandatory, so very large source text or the latest turn can exceed the soft budget
/// instead of being silently truncated.
struct AiHistoryWindow {
    static let standard = AiHistoryWindow(maxContentCharacters: 48_000)

    let maxContentCharacters: Int

    init(maxContentCharacters: Int) {
        precondition(maxContentCharacters > 0)
        self.maxContentCharacters = maxContentCharacters
    }

    func requestMessages(from messages: [AiMessage]) -> [AiMessage] {
        guard !messages.isEmpty else { return [] }

        let split = anchorSplitIndex(in: messages)
        let anchors = Array(messages[..<split])
        let conversation = Array(messages[split...])
        guard !conversation.isEmpty else { return anchors }

        let units = newestFirstUnits(from: conversation)
        guard !units.isEmpty else { return anchors }

        var usedCharacters = anchors.reduce(0) { $0 + $1.content.count }
        var selectedNewestFirst: [[AiMessage]] = []

        for (index, unit) in units.enumerated() {
            let unitCharacters = unit.reduce(0) { $0 + $1.content.count }
            let isMandatoryNewestUnit = index == 0
            guard isMandatoryNewestUnit || usedCharacters + unitCharacters <= maxContentCharacters else {
                break
            }

            selectedNewestFirst.append(unit)
            usedCharacters += unitCharacters
        }

        return anchors + selectedNewestFirst.reversed().flatMap { $0 }
    }

    private func anchorSplitIndex(in messages: [AiMessage]) -> Int {
        var index = 0

        if messages.indices.contains(index), messages[index].role == .system {
            index += 1
        }

        if messages.indices.contains(index),
           messages[index].role == .user,
           !messages[index].isVisible {
            index += 1
        }

        return index
    }

    /// Returns contiguous conversation units from newest to oldest. If the request ends
    /// with a pending user message, the newest unit also keeps the immediately preceding
    /// assistant response and its user question when present. This prevents a follow-up
    /// such as “why?” from being detached from the answer it directly references.
    private func newestFirstUnits(from messages: [AiMessage]) -> [[AiMessage]] {
        guard !messages.isEmpty else { return [] }

        var units: [[AiMessage]] = []
        var index = messages.count - 1

        if messages[index].role == .user {
            var newestUnit = [messages[index]]
            index -= 1

            if index >= 0, messages[index].role == .assistant {
                newestUnit.insert(messages[index], at: 0)
                index -= 1

                if index >= 0, messages[index].role == .user {
                    newestUnit.insert(messages[index], at: 0)
                    index -= 1
                }
            }

            units.append(newestUnit)
        }

        while index >= 0 {
            let message = messages[index]

            if message.role == .assistant,
               index > 0,
               messages[index - 1].role == .user {
                units.append([messages[index - 1], message])
                index -= 2
            } else {
                units.append([message])
                index -= 1
            }
        }

        return units
    }
}
