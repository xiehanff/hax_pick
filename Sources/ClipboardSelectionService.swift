import AppKit

enum ClipboardSelectionService {
    static let simulatedCopyEventTag: Int64 = 0x4841585049434B // "HAXPICK"

    static func selectedTextBySimulatedCopy(
        allowAppleScriptFallback: Bool = true,
        timeout: TimeInterval = 0.4,
        userCopyShortcutDetected: @escaping (Date) -> Bool = { _ in false }
    ) async -> String? {
        // 通道 2a: CGEvent 模拟 ⌘C
        if let text = await copyViaCGEvent(
            timeout: timeout,
            userCopyShortcutDetected: userCopyShortcutDetected
        ) {
            return text
        }
        guard allowAppleScriptFallback, !Task.isCancelled else { return nil }
        // 通道 2b: AppleScript 兜底
        return await copyViaAppleScript(
            timeout: timeout,
            userCopyShortcutDetected: userCopyShortcutDetected
        )
    }

    // MARK: - CGEvent 方案

    private static func copyViaCGEvent(
        timeout: TimeInterval,
        userCopyShortcutDetected: @escaping (Date) -> Bool
    ) async -> String? {
        return await performSimulatedCopy(
            using: simulateCommandC,
            timeout: timeout,
            userCopyShortcutDetected: userCopyShortcutDetected
        )
    }

    private static func simulateCommandC() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: simulatedCopyEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: simulatedCopyEventTag)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - AppleScript 兜底

    private static func copyViaAppleScript(
        timeout: TimeInterval,
        userCopyShortcutDetected: @escaping (Date) -> Bool
    ) async -> String? {
        return await performSimulatedCopy(
            using: {
                let script = "tell application \"System Events\" to keystroke \"c\" using command down"
                let process = Process()
                process.launchPath = "/usr/bin/osascript"
                process.arguments = ["-e", script]
                try? process.run()
                process.waitUntilExit()
            },
            timeout: timeout,
            userCopyShortcutDetected: userCopyShortcutDetected
        )
    }

    // MARK: - 公共复制逻辑

    private static func performSimulatedCopy(
        using copyAction: () -> Void,
        timeout: TimeInterval,
        userCopyShortcutDetected: @escaping (Date) -> Bool
    ) async -> String? {
        // 最终探测等待期间可能已经开始下一次拖动，不能向按住鼠标的应用注入按键。
        guard !Task.isCancelled,
              !CGEventSource.buttonState(.combinedSessionState, button: .left) else { return nil }
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let baselineChangeCount = pasteboard.changeCount
        let fallbackStartedAt = Date()

        // 不要先向系统剪贴板写入 marker。部分终端/TUI 不会响应模拟 ⌘C，
        // marker 可能因此成为用户最终看到的剪贴板内容。直接用 changeCount
        // 判断复制动作是否真正写入，等待期间也不会污染原剪贴板。
        copyAction()
        let observation = await waitForPasteboardResult(
            pasteboard: pasteboard,
            baselineChangeCount: baselineChangeCount,
            fallbackStartedAt: fallbackStartedAt,
            timeout: timeout,
            userCopyShortcutDetected: userCopyShortcutDetected
        )

        switch observation.result {
        case .copiedText(let text):
            restoreSnapshotIfUnchanged(
                snapshot,
                to: pasteboard,
                expectedChangeCount: observation.changeCount
            )
            return text
        case .timedOut:
            // 未发生变化时剪贴板本来就是原快照；发生变化时保留新内容，
            // 避免覆盖用户或其他应用在等待期间写入的内容。
            return nil
        case .externalWrite:
            return nil
        }
    }

    private static func waitForPasteboardResult(
        pasteboard: NSPasteboard,
        baselineChangeCount: Int,
        fallbackStartedAt: Date,
        timeout: TimeInterval,
        userCopyShortcutDetected: @escaping (Date) -> Bool
    ) async -> PasteboardCopyObservation {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if Task.isCancelled {
                return PasteboardCopyObservation(
                    result: .timedOut,
                    changeCount: pasteboard.changeCount
                )
            }

            let observedChangeCount = pasteboard.changeCount
            let currentString = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let didChangeExternally = pasteboardChanged(
                since: baselineChangeCount,
                currentChangeCount: observedChangeCount
            )
            let didDetectUserCopyShortcut = userCopyShortcutDetected(fallbackStartedAt)

            if let result = classifyPasteboardObservation(
                currentString: currentString,
                didChangeExternally: didChangeExternally,
                didDetectUserCopyShortcut: didDetectUserCopyShortcut
            ) {
                return PasteboardCopyObservation(
                    result: result,
                    changeCount: observedChangeCount
                )
            }

            do {
                try await Task.sleep(nanoseconds: 20_000_000)
            } catch {
                return PasteboardCopyObservation(
                    result: .timedOut,
                    changeCount: pasteboard.changeCount
                )
            }
        }

        return PasteboardCopyObservation(
            result: .timedOut,
            changeCount: pasteboard.changeCount
        )
    }

    static func pasteboardChanged(since baselineChangeCount: Int, currentChangeCount: Int) -> Bool {
        currentChangeCount != baselineChangeCount
    }

    static func shouldRestoreSnapshot(observedChangeCount: Int, currentChangeCount: Int) -> Bool {
        observedChangeCount == currentChangeCount
    }

    static func classifyPasteboardObservation(
        currentString: String?,
        didChangeExternally: Bool,
        didDetectUserCopyShortcut: Bool
    ) -> PasteboardCopyResult? {
        if didDetectUserCopyShortcut,
           let currentString,
           !currentString.isEmpty {
            return .externalWrite
        }

        if let currentString, !currentString.isEmpty, didChangeExternally {
            return .copiedText(currentString)
        }

        if didDetectUserCopyShortcut, didChangeExternally {
            return .externalWrite
        }

        if currentString == nil, didChangeExternally {
            return .externalWrite
        }

        return nil
    }

    private static func restoreSnapshotIfUnchanged(
        _ snapshot: PasteboardSnapshot,
        to pasteboard: NSPasteboard,
        expectedChangeCount: Int
    ) {
        guard shouldRestoreSnapshot(
            observedChangeCount: expectedChangeCount,
            currentChangeCount: pasteboard.changeCount
        ) else {
            return
        }
        snapshot.restore(to: pasteboard)
    }
}

enum PasteboardCopyResult: Equatable {
    case copiedText(String)
    case externalWrite
    case timedOut
}

private struct PasteboardCopyObservation {
    let result: PasteboardCopyResult
    let changeCount: Int
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let snapshots = (pasteboard.pasteboardItems ?? []).map { item in
            var storedTypes: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                storedTypes[type] = data
            }
            return storedTypes
        }
        return PasteboardSnapshot(items: snapshots)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { storedTypes -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in storedTypes {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
