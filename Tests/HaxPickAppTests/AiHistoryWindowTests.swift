import XCTest
@testable import HaxPickApp

final class AiHistoryWindowTests: XCTestCase {
    func testPreservesAnchorsAndNewestCompleteTurnsWithinBudget() {
        let system = AiMessage(role: .system, content: "sys", isVisible: false)
        let source = AiMessage(role: .user, content: "source", isVisible: false)
        let a0 = AiMessage(role: .assistant, content: "A000")
        let q1 = AiMessage(role: .user, content: "Q111")
        let a1 = AiMessage(role: .assistant, content: "A111")
        let q2 = AiMessage(role: .user, content: "Q222")

        let window = AiHistoryWindow(maxContentCharacters: 21)
        let result = window.requestMessages(from: [system, source, a0, q1, a1, q2])

        XCTAssertEqual(result.map(\.id), [system.id, source.id, q1.id, a1.id, q2.id])
    }

    func testNeverTruncatesAnchorsOrDirectFollowUpDependency() {
        let system = AiMessage(role: .system, content: String(repeating: "s", count: 20), isVisible: false)
        let source = AiMessage(role: .user, content: String(repeating: "x", count: 20), isVisible: false)
        let previousAnswer = AiMessage(role: .assistant, content: String(repeating: "a", count: 30))
        let newestQuestion = AiMessage(role: .user, content: String(repeating: "q", count: 30))

        let window = AiHistoryWindow(maxContentCharacters: 10)
        let result = window.requestMessages(from: [system, source, previousAnswer, newestQuestion])

        XCTAssertEqual(result.map(\.id), [system.id, source.id, previousAnswer.id, newestQuestion.id])
    }

    func testNewestPendingQuestionKeepsPreviousExchangeEvenWhenItExceedsBudget() {
        let system = AiMessage(role: .system, content: "sys", isVisible: false)
        let source = AiMessage(role: .user, content: "src", isVisible: false)
        let a0 = AiMessage(role: .assistant, content: "old-initial")
        let q1 = AiMessage(role: .user, content: String(repeating: "q", count: 20))
        let a1 = AiMessage(role: .assistant, content: String(repeating: "a", count: 20))
        let q2 = AiMessage(role: .user, content: "why?")

        let window = AiHistoryWindow(maxContentCharacters: 12)
        let result = window.requestMessages(from: [system, source, a0, q1, a1, q2])

        XCTAssertEqual(result.map(\.id), [system.id, source.id, q1.id, a1.id, q2.id])
    }

    func testDoesNotStartWindowWithOrphanedAssistant() {
        let system = AiMessage(role: .system, content: "sys", isVisible: false)
        let source = AiMessage(role: .user, content: "src", isVisible: false)
        let q1 = AiMessage(role: .user, content: "question-one")
        let a1 = AiMessage(role: .assistant, content: "answer-one")
        let q2 = AiMessage(role: .user, content: "question-two")
        let a2 = AiMessage(role: .assistant, content: "answer-two")
        let q3 = AiMessage(role: .user, content: "latest")

        let budget = system.content.count + source.content.count + q2.content.count + a2.content.count + q3.content.count
        let window = AiHistoryWindow(maxContentCharacters: budget)
        let result = window.requestMessages(from: [system, source, q1, a1, q2, a2, q3])

        XCTAssertEqual(result.map(\.id), [system.id, source.id, q2.id, a2.id, q3.id])
    }

    func testLocalMessagesAreNotMutatedByWindowing() {
        let messages = [
            AiMessage(role: .system, content: "sys", isVisible: false),
            AiMessage(role: .user, content: "src", isVisible: false),
            AiMessage(role: .assistant, content: "first"),
            AiMessage(role: .user, content: "second"),
        ]
        let original = messages

        _ = AiHistoryWindow(maxContentCharacters: 8).requestMessages(from: messages)

        XCTAssertEqual(messages, original)
    }
}
