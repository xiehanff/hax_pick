import XCTest
@testable import HaxPickApp

@MainActor
final class AiRequestRevisionTests: XCTestCase {
    func testEveryStartedRequestAdvancesRevisionExactlyOnce() async throws {
        let responder = ImmediateResponder(outputs: ["A0", "A1", "A1-new"])
        let session = AiAgentSession(complete: { try await responder.complete($0) })

        XCTAssertEqual(session.requestRevision, 0)

        session.runToolAction(.explain, sourceText: "source")
        XCTAssertEqual(session.requestRevision, 1)
        try await waitForCompletedAssistant(session, content: "A0")

        XCTAssertTrue(session.sendMessage("Q1"))
        XCTAssertEqual(session.requestRevision, 2)
        try await waitForCompletedAssistant(session, content: "A1")

        session.retry()
        XCTAssertEqual(session.requestRevision, 3)
        try await waitForCompletedAssistant(session, content: "A1-new")
    }

    private func waitForCompletedAssistant(_ session: AiAgentSession, content: String) async throws {
        for _ in 0..<800 {
            if !session.isLoading && session.lastAssistantContent == content {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected assistant response \(content)")
        throw RequestRevisionTestError.conditionNotMet
    }
}

private enum RequestRevisionTestError: Error {
    case conditionNotMet
}

@MainActor
private final class ImmediateResponder {
    private var outputs: [String]

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func complete(_ messages: [AiMessage]) async throws -> String {
        guard !outputs.isEmpty else {
            throw RequestRevisionTestError.conditionNotMet
        }
        return outputs.removeFirst()
    }
}
