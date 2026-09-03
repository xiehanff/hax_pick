import XCTest
@testable import HaxPickApp

final class ChatFollowTailStateTests: XCTestCase {
    func testManualScrollPausesFollowingUntilResume() {
        var state = ChatFollowTailState()

        XCTAssertTrue(state.isFollowingTail)
        state.userDidScroll()
        XCTAssertFalse(state.isFollowingTail)

        state.resume()
        XCTAssertTrue(state.isFollowingTail)
    }

    func testStartingNewRequestRestoresFollowing() {
        var state = ChatFollowTailState()
        state.userDidScroll()
        XCTAssertFalse(state.isFollowingTail)

        state.requestDidStart()
        XCTAssertTrue(state.isFollowingTail)
    }
}
