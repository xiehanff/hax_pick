import XCTest
@testable import HaxPickApp

final class ClipboardSelectionServiceTests: XCTestCase {
    private let marker = "HaxPick-1234"

    func testClipboardFallbackTextContexts() {
        for attribute in [kAXSelectedTextAttribute, kAXNumberOfCharactersAttribute] {
            XCTAssertTrue(
                AccessibilityTextService.shouldUseClipboardFallback(
                    attributeNames: [attribute as String]
                )
            )
        }

        for role in ["AXWebArea", "AXStaticText", "AXTextArea", "AXTextField"] {
            XCTAssertTrue(
                AccessibilityTextService.shouldUseClipboardFallback(
                    attributeNames: [],
                    role: role
                ),
                "Expected clipboard fallback for \(role)"
            )
        }

        XCTAssertFalse(
            AccessibilityTextService.shouldUseClipboardFallback(
                attributeNames: [kAXRoleAttribute as String, kAXTitleAttribute as String]
            )
        )
    }

    func testKnownBrowserAndIDEApplications() {
        let supported = [
            "com.google.Chrome",
            "com.apple.dt.Xcode",
            "com.microsoft.VSCode",
            "com.openai.codex",
            "com.jetbrains.intellij",
        ]

        for bundleIdentifier in supported {
            XCTAssertTrue(
                AccessibilityTextService.isKnownTextSelectionApplication(
                    bundleIdentifier: bundleIdentifier
                ),
                "Expected clipboard fallback for \(bundleIdentifier)"
            )
        }
        XCTAssertFalse(
            AccessibilityTextService.isKnownTextSelectionApplication(
                bundleIdentifier: "com.apple.finder"
            )
        )
    }

    func testPasteboardObservationClassification() {
        let scenarios: [(text: String?, changed: Bool, userCopy: Bool, expected: PasteboardCopyResult?)] = [
            ("copied text", true, false, .copiedText("copied text")),
            (nil, true, false, .externalWrite),
            (marker, false, false, nil),
            ("", false, false, nil),
            ("manual copy", true, true, .externalWrite),
        ]

        for scenario in scenarios {
            let result = ClipboardSelectionService.classifyPasteboardObservation(
                currentString: scenario.text,
                marker: marker,
                didChangeExternally: scenario.changed,
                didDetectUserCopyShortcut: scenario.userCopy
            )
            XCTAssertEqual(result, scenario.expected)
        }
    }
}
