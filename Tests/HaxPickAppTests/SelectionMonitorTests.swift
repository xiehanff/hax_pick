import AppKit
import XCTest
@testable import HaxPickApp

@MainActor
final class SelectionMonitorTests: XCTestCase {
    private let startPoint = NSPoint(x: 10, y: 20)
    private let endPoint = NSPoint(x: 50, y: 60)

    func testMouseDragPublishesSelectionBeforeMouseUp() async {
        let detected = expectation(description: "selection detected while dragging")
        var detectedText: String?
        let monitor = makeMonitor(
            onSelectionDetected: {
                detectedText = $0.text
                detected.fulfill()
            },
            shouldAttemptClipboardFallback: { _, _ in true },
            earlyClipboardFallback: { "first-word" }
        )

        monitor.handleMouseDown(at: startPoint)
        monitor.handleMouseDragged(to: endPoint)

        await fulfillment(of: [detected], timeout: 1)
        XCTAssertEqual(detectedText, "first-word")
        monitor.stop()
    }

    func testFinalSelectionPrefersAccessibility() async {
        let expected = snapshot("from-ax")
        let monitor = makeMonitor(
            accessibilitySnapshot: { _, _, _ in expected },
            shouldAttemptClipboardFallback: { _, _ in true },
            clipboardFallback: { "from-clipboard" }
        )

        let result = await resolveFinalSelection(with: monitor)

        XCTAssertEqual(result?.text, expected.text)
        XCTAssertEqual(result?.anchorPoint, expected.anchorPoint)
    }

    func testFinalSelectionUsesClipboardWhenAllowed() async {
        let monitor = makeMonitor(
            shouldAttemptClipboardFallback: { _, _ in true },
            clipboardFallback: { "from-clipboard" }
        )

        let result = await resolveFinalSelection(with: monitor)

        XCTAssertEqual(result?.text, "from-clipboard")
        XCTAssertEqual(result?.anchorPoint, startPoint.midpoint(to: endPoint))
    }

    func testFinalSelectionReturnsNilWhenFallbackUnavailable() async {
        let scenarios: [(allowed: Bool, clipboardText: String?)] = [
            (false, "unreachable"),
            (true, nil),
        ]

        for scenario in scenarios {
            let monitor = makeMonitor(
                shouldAttemptClipboardFallback: { _, _ in scenario.allowed },
                clipboardFallback: { scenario.clipboardText }
            )
            let result = await resolveFinalSelection(with: monitor)
            XCTAssertNil(result)
        }
    }

    func testFinalSelectionUsesCapturedFocusedElement() async {
        let focusedElement = AXUIElementCreateSystemWide()
        var receivedElement: AXUIElement?
        let monitor = makeMonitor(
            accessibilitySnapshot: { element, _, _ in
                receivedElement = element
                return nil
            },
            shouldAttemptClipboardFallback: { element, _ in
                receivedElement = element
                return element != nil
            },
            clipboardFallback: { "from-clipboard" }
        )

        let result = await monitor.resolveSelectionSnapshot(
            focusedElement: focusedElement,
            dragStartPoint: startPoint,
            releasePoint: endPoint
        )

        XCTAssertNotNil(receivedElement)
        XCTAssertEqual(result?.text, "from-clipboard")
    }

    func testFinalSelectionFallsBackToEarlyAccessibilitySnapshot() async {
        let expected = snapshot("early-selection")
        let result = await makeMonitor().resolveSelectionSnapshot(
            earlyAccessibilitySnapshot: expected,
            dragStartPoint: startPoint,
            releasePoint: endPoint
        )

        XCTAssertEqual(result?.text, expected.text)
        XCTAssertEqual(result?.anchorPoint, expected.anchorPoint)
    }

    func testDragSelectionUsesFastClipboardPath() async {
        var fallbackPoint: NSPoint?
        var usedFinalFallback = false
        let monitor = makeMonitor(
            shouldAttemptClipboardFallback: { _, point in
                fallbackPoint = point
                return true
            },
            clipboardFallback: {
                usedFinalFallback = true
                return "final-selection"
            },
            earlyClipboardFallback: { "selection-in-progress" }
        )

        let result = await monitor.resolveSelectionDuringDrag(
            focusedElement: nil,
            dragStartPoint: startPoint,
            currentPoint: endPoint
        )

        XCTAssertEqual(result?.text, "selection-in-progress")
        XCTAssertEqual(result?.anchorPoint, startPoint.midpoint(to: endPoint))
        XCTAssertEqual(fallbackPoint, endPoint)
        XCTAssertFalse(usedFinalFallback)
    }

    func testDragSelectionPrefersAccessibility() async {
        let expected = snapshot("first-word")
        let monitor = makeMonitor(
            accessibilitySnapshot: { _, _, _ in expected },
            shouldAttemptClipboardFallback: { _, _ in true },
            earlyClipboardFallback: { "clipboard-selection" }
        )

        let result = await monitor.resolveSelectionDuringDrag(
            focusedElement: nil,
            dragStartPoint: startPoint,
            currentPoint: endPoint
        )

        XCTAssertEqual(result?.text, expected.text)
        XCTAssertEqual(result?.anchorPoint, expected.anchorPoint)
    }

    private func resolveFinalSelection(with monitor: SelectionMonitor) async -> TextSelectionSnapshot? {
        await monitor.resolveSelectionSnapshot(
            dragStartPoint: startPoint,
            releasePoint: endPoint
        )
    }

    private func snapshot(_ text: String) -> TextSelectionSnapshot {
        TextSelectionSnapshot(text: text, anchorPoint: NSPoint(x: 30, y: 40))
    }

    private func makeMonitor(
        onSelectionDetected: @escaping (TextSelectionSnapshot) -> Void = { _ in },
        accessibilitySnapshot: @escaping (AXUIElement?, NSPoint, NSPoint) -> TextSelectionSnapshot? = { _, _, _ in nil },
        shouldAttemptClipboardFallback: @escaping (AXUIElement?, NSPoint) -> Bool = { _, _ in false },
        clipboardFallback: @escaping () async -> String? = { nil },
        earlyClipboardFallback: (() async -> String?)? = nil
    ) -> SelectionMonitor {
        SelectionMonitor(
            onSelectionDetected: onSelectionDetected,
            onSelectionMissed: {},
            focusedElementSnapshotProvider: { nil },
            accessibilitySnapshotProvider: accessibilitySnapshot,
            shouldAttemptClipboardFallbackProvider: shouldAttemptClipboardFallback,
            clipboardFallbackProvider: clipboardFallback,
            earlyClipboardFallbackProvider: earlyClipboardFallback
        )
    }
}
