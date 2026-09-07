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

    func testReturningToViewportBottomRestoresFollowingAutomatically() {
        var state = ChatFollowTailState()
        state.userDidScroll()
        XCTAssertFalse(state.isFollowingTail)

        XCTAssertFalse(
            state.tailPositionDidChange(
                tailMaxY: 520,
                viewportHeight: 420
            )
        )
        XCTAssertFalse(state.isFollowingTail)

        XCTAssertTrue(
            state.tailPositionDidChange(
                tailMaxY: 448,
                viewportHeight: 420
            )
        )
        XCTAssertTrue(state.isFollowingTail)
    }

    func testTailGeometryDoesNotChangeAnAlreadyFollowingState() {
        var state = ChatFollowTailState()

        XCTAssertFalse(
            state.tailPositionDidChange(
                tailMaxY: 410,
                viewportHeight: 420
            )
        )
        XCTAssertTrue(state.isFollowingTail)
    }
}
