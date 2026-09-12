import XCTest
@testable import HaxPickApp

final class ClipboardSelectionServiceTests: XCTestCase {
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
            ("old clipboard text", false, false, nil),
            ("", false, false, nil),
            ("manual copy", true, true, .externalWrite),
        ]

        for scenario in scenarios {
            let result = ClipboardSelectionService.classifyPasteboardObservation(
                currentString: scenario.text,
                didChangeExternally: scenario.changed,
                didDetectUserCopyShortcut: scenario.userCopy
            )
            XCTAssertEqual(result, scenario.expected)
        }
    }

    func testPasteboardChangeIsMeasuredFromBaseline() {
        XCTAssertFalse(
            ClipboardSelectionService.pasteboardChanged(
                since: 42,
                currentChangeCount: 42
            )
        )
        XCTAssertTrue(
            ClipboardSelectionService.pasteboardChanged(
                since: 42,
                currentChangeCount: 43
            )
        )
    }

    func testSnapshotRestoreRequiresUnchangedObservationVersion() {
        XCTAssertTrue(
            ClipboardSelectionService.shouldRestoreSnapshot(
                observedChangeCount: 100,
                currentChangeCount: 100
            )
        )
        XCTAssertFalse(
            ClipboardSelectionService.shouldRestoreSnapshot(
                observedChangeCount: 100,
                currentChangeCount: 101
            ),
            "观察到复制结果之后若剪贴板再次变化，就不能恢复旧快照覆盖新内容"
        )
    }
}
