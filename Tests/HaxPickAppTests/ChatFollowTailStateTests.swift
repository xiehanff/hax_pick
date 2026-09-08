import XCTest
@testable import HaxPickApp

final class ChatFollowTailStateTests: XCTestCase {
    func testLeavingTailPausesFollowing() {
        var state = ChatFollowTailState()

        XCTAssertTrue(state.isFollowingTail)
        XCTAssertEqual(
            state.userScrollPositionDidChange(extentAfter: 120),
            .paused
        )
        XCTAssertFalse(state.isFollowingTail)
    }

    func testStartingNewRequestRestoresFollowing() {
        var state = ChatFollowTailState()
        _ = state.userScrollPositionDidChange(extentAfter: 120)
        XCTAssertFalse(state.isFollowingTail)

        state.requestDidStart()
        XCTAssertTrue(state.isFollowingTail)
    }

    func testReturningToTailRestoresFollowingRegardlessOfDirectionHistory() {
        var state = ChatFollowTailState()
        _ = state.userScrollPositionDidChange(extentAfter: 120)
        XCTAssertFalse(state.isFollowingTail)

        XCTAssertEqual(
            state.userScrollPositionDidChange(extentAfter: 80),
            .none
        )
        XCTAssertFalse(state.isFollowingTail)

        XCTAssertEqual(
            state.userScrollPositionDidChange(extentAfter: 12),
            .resumed
        )
        XCTAssertTrue(state.isFollowingTail)
    }

    func testSmallMovementInsideTailToleranceKeepsFollowing() {
        var state = ChatFollowTailState()

        XCTAssertEqual(
            state.userScrollPositionDidChange(extentAfter: 18),
            .none
        )
        XCTAssertTrue(state.isFollowingTail)
    }

    func testResumeIsIdempotent() {
        var state = ChatFollowTailState()
        _ = state.userScrollPositionDidChange(extentAfter: 120)
        XCTAssertFalse(state.isFollowingTail)

        state.resume()
        XCTAssertTrue(state.isFollowingTail)
        XCTAssertEqual(
            state.userScrollPositionDidChange(extentAfter: 0),
            .none
        )
    }
}
