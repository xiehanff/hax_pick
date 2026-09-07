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

    func testReturningTowardTailWithinThresholdRestoresFollowing() {
        var state = ChatFollowTailState()
        state.userDidScroll()
        XCTAssertFalse(state.isFollowingTail)

        XCTAssertFalse(
            state.tailPositionDidChange(
                extentAfter: 120,
                movingTowardTail: true
            )
        )
        XCTAssertFalse(state.isFollowingTail)

        XCTAssertTrue(
            state.tailPositionDidChange(
                extentAfter: 40,
                movingTowardTail: true
            )
        )
        XCTAssertTrue(state.isFollowingTail)
    }

    func testMovingAwayFromTailDoesNotImmediatelyResumeInsideThreshold() {
        var state = ChatFollowTailState()
        state.userDidScroll()
        XCTAssertFalse(state.isFollowingTail)

        XCTAssertFalse(
            state.tailPositionDidChange(
                extentAfter: 24,
                movingTowardTail: false
            )
        )
        XCTAssertFalse(state.isFollowingTail)
    }

    func testTailMetricDoesNotChangeAnAlreadyFollowingState() {
        var state = ChatFollowTailState()

        XCTAssertFalse(
            state.tailPositionDidChange(
                extentAfter: 0,
                movingTowardTail: true
            )
        )
        XCTAssertTrue(state.isFollowingTail)
    }
}
