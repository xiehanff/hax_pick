import XCTest
@testable import HaxPickApp

final class ClipboardSelectionServiceTests: XCTestCase {
    func testShouldUseClipboardFallbackReturnsTrueForTextAttributes() {
        XCTAssertTrue(
            AccessibilityTextService.shouldUseClipboardFallback(
                attributeNames: [kAXSelectedTextAttribute as String]
            )
        )
        XCTAssertTrue(
            AccessibilityTextService.shouldUseClipboardFallback(
                attributeNames: [kAXNumberOfCharactersAttribute as String]
            )
        )
    }

    func testShouldUseClipboardFallbackReturnsFalseForNonTextAttributes() {
        XCTAssertFalse(
            AccessibilityTextService.shouldUseClipboardFallback(
                attributeNames: [kAXRoleAttribute as String, kAXTitleAttribute as String]
            )
        )
    }

    func testShouldUseClipboardFallbackReturnsTrueForBrowserWebAreaRole() {
        XCTAssertTrue(
            AccessibilityTextService.shouldUseClipboardFallback(
                attributeNames: [kAXRoleAttribute as String],
                role: "AXWebArea"
            )
        )
    }

    func testClassifyPasteboardObservationReturnsCopiedText() {
        let result = ClipboardSelectionService.classifyPasteboardObservation(
            currentString: "copied text",
            marker: "HaxPick-1234",
            didChangeExternally: true,
            didDetectUserCopyShortcut: false
        )

        XCTAssertEqual(result, .copiedText("copied text"))
    }

    func testClassifyPasteboardObservationReturnsExternalWriteForNonTextContent() {
        let result = ClipboardSelectionService.classifyPasteboardObservation(
            currentString: nil,
            marker: "HaxPick-1234",
            didChangeExternally: true,
            didDetectUserCopyShortcut: false
        )

        XCTAssertEqual(result, .externalWrite)
    }

    func testClassifyPasteboardObservationKeepsWaitingForMarker() {
        let result = ClipboardSelectionService.classifyPasteboardObservation(
            currentString: "HaxPick-1234",
            marker: "HaxPick-1234",
            didChangeExternally: false,
            didDetectUserCopyShortcut: false
        )

        XCTAssertNil(result)
    }

    func testClassifyPasteboardObservationKeepsWaitingForEmptyString() {
        let result = ClipboardSelectionService.classifyPasteboardObservation(
            currentString: "",
            marker: "HaxPick-1234",
            didChangeExternally: false,
            didDetectUserCopyShortcut: false
        )

        XCTAssertNil(result)
    }

    func testClassifyPasteboardObservationTreatsUserCommandCAsExternalWrite() {
        let result = ClipboardSelectionService.classifyPasteboardObservation(
            currentString: "manual copy",
            marker: "HaxPick-1234",
            didChangeExternally: true,
            didDetectUserCopyShortcut: true
        )

        XCTAssertEqual(result, .externalWrite)
    }
}
