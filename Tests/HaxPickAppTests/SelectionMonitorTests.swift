import AppKit
import XCTest
@testable import HaxPickApp

@MainActor
final class SelectionMonitorTests: XCTestCase {
    func testResolveSelectionSnapshotReturnsAccessibilityResultFirst() async {
        let expected = TextSelectionSnapshot(
            text: "from-ax",
            anchorPoint: NSPoint(x: 30, y: 40)
        )
        let monitor = SelectionMonitor(
            onSelectionDetected: { _ in },
            onSelectionMissed: {},
            focusedElementSnapshotProvider: { nil },
            accessibilitySnapshotProvider: { _, _, _ in expected },
            shouldAttemptClipboardFallbackProvider: { _ in false },
            clipboardFallbackProvider: { "from-clipboard" }
        )

        let snapshot = await monitor.resolveSelectionSnapshot(
            focusedElement: nil,
            dragStartPoint: NSPoint(x: 10, y: 20),
            releasePoint: NSPoint(x: 50, y: 60)
        )

        XCTAssertEqual(snapshot?.text, "from-ax")
        XCTAssertEqual(snapshot?.anchorPoint, expected.anchorPoint)
    }

    func testResolveSelectionSnapshotReturnsNilWhenFallbackIsDisallowed() async {
        let monitor = SelectionMonitor(
            onSelectionDetected: { _ in },
            onSelectionMissed: {},
            focusedElementSnapshotProvider: { nil },
            accessibilitySnapshotProvider: { _, _, _ in nil },
            shouldAttemptClipboardFallbackProvider: { _ in false },
            clipboardFallbackProvider: { "from-clipboard" }
        )

        let snapshot = await monitor.resolveSelectionSnapshot(
            focusedElement: nil,
            dragStartPoint: NSPoint(x: 0, y: 0),
            releasePoint: NSPoint(x: 20, y: 20)
        )

        XCTAssertNil(snapshot)
    }

    func testResolveSelectionSnapshotUsesClipboardFallbackWhenAllowed() async {
        let dragStartPoint = NSPoint(x: 10, y: 20)
        let releasePoint = NSPoint(x: 30, y: 60)
        let expectedAnchorPoint = dragStartPoint.midpoint(to: releasePoint)
        let monitor = SelectionMonitor(
            onSelectionDetected: { _ in },
            onSelectionMissed: {},
            focusedElementSnapshotProvider: { nil },
            accessibilitySnapshotProvider: { _, _, _ in nil },
            shouldAttemptClipboardFallbackProvider: { _ in true },
            clipboardFallbackProvider: { "from-clipboard" }
        )

        let snapshot = await monitor.resolveSelectionSnapshot(
            focusedElement: nil,
            dragStartPoint: dragStartPoint,
            releasePoint: releasePoint
        )

        XCTAssertEqual(snapshot?.text, "from-clipboard")
        XCTAssertEqual(snapshot?.anchorPoint, expectedAnchorPoint)
    }

    func testResolveSelectionSnapshotReturnsNilWhenClipboardFallbackFails() async {
        let monitor = SelectionMonitor(
            onSelectionDetected: { _ in },
            onSelectionMissed: {},
            focusedElementSnapshotProvider: { nil },
            accessibilitySnapshotProvider: { _, _, _ in nil },
            shouldAttemptClipboardFallbackProvider: { _ in true },
            clipboardFallbackProvider: { nil }
        )

        let snapshot = await monitor.resolveSelectionSnapshot(
            focusedElement: nil,
            dragStartPoint: NSPoint(x: 5, y: 5),
            releasePoint: NSPoint(x: 15, y: 25)
        )

        XCTAssertNil(snapshot)
    }

    func testResolveSelectionSnapshotUsesCapturedFocusedElementForFallbackDecision() async {
        var receivedFocusedElement: AXUIElement?
        let focusedElement = AXUIElementCreateSystemWide()
        let monitor = SelectionMonitor(
            onSelectionDetected: { _ in },
            onSelectionMissed: {},
            focusedElementSnapshotProvider: { focusedElement },
            accessibilitySnapshotProvider: { element, _, _ in
                receivedFocusedElement = element
                return nil
            },
            shouldAttemptClipboardFallbackProvider: { element in
                receivedFocusedElement = element
                return element != nil
            },
            clipboardFallbackProvider: { "from-clipboard" }
        )

        let snapshot = await monitor.resolveSelectionSnapshot(
            focusedElement: focusedElement,
            dragStartPoint: NSPoint(x: 10, y: 10),
            releasePoint: NSPoint(x: 30, y: 30)
        )

        XCTAssertNotNil(receivedFocusedElement)
        XCTAssertEqual(snapshot?.text, "from-clipboard")
    }

    func testResolveSelectionSnapshotFallsBackToEarlyAccessibilitySnapshot() async {
        let earlySnapshot = TextSelectionSnapshot(
            text: "early-selection",
            anchorPoint: NSPoint(x: 12, y: 34)
        )
        let monitor = SelectionMonitor(
            onSelectionDetected: { _ in },
            onSelectionMissed: {},
            focusedElementSnapshotProvider: { nil },
            accessibilitySnapshotProvider: { _, _, _ in nil },
            shouldAttemptClipboardFallbackProvider: { _ in false },
            clipboardFallbackProvider: { nil }
        )

        let snapshot = await monitor.resolveSelectionSnapshot(
            earlyAccessibilitySnapshot: earlySnapshot,
            focusedElement: nil,
            dragStartPoint: NSPoint(x: 10, y: 20),
            releasePoint: NSPoint(x: 30, y: 40)
        )

        XCTAssertEqual(snapshot?.text, "early-selection")
        XCTAssertEqual(snapshot?.anchorPoint, earlySnapshot.anchorPoint)
    }
}
