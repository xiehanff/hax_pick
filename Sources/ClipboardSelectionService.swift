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
        let marker = "HaxPick-\(UUID().uuidString.prefix(8))"
        let fallbackStartedAt = Date()

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        let markerChangeCount = pasteboard.changeCount

        copyAction()
        let observation = await waitForPasteboardResult(
            pasteboard: pasteboard,
            marker: marker,
            markerChangeCount: markerChangeCount,
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
            // 只有 marker 写入之后再无任何剪贴板变化时才恢复旧快照。
            // 一旦出现无法归因的变化，宁可保留新内容，也不能覆盖用户/其他应用的写入。
            if observation.changeCount == markerChangeCount {
                restoreSnapshotIfUnchanged(
                    snapshot,
                    to: pasteboard,
                    expectedChangeCount: markerChangeCount
                )
            }
            return nil
        case .externalWrite:
            return nil
        }
    }

    private static func waitForPasteboardResult(
        pasteboard: NSPasteboard,
        marker: String,
        markerChangeCount: Int,
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
                since: markerChangeCount,
                currentChangeCount: observedChangeCount
            )
            let didDetectUserCopyShortcut = userCopyShortcutDetected(fallbackStartedAt)

            if let result = classifyPasteboardObservation(
                currentString: currentString,
                marker: marker,
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

    static func pasteboardChanged(since markerChangeCount: Int, currentChangeCount: Int) -> Bool {
        currentChangeCount != markerChangeCount
    }

    static func shouldRestoreSnapshot(observedChangeCount: Int, currentChangeCount: Int) -> Bool {
        observedChangeCount == currentChangeCount
    }

    static func classifyPasteboardObservation(
        currentString: String?,
        marker: String,
        didChangeExternally: Bool,
        didDetectUserCopyShortcut: Bool
    ) -> PasteboardCopyResult? {
        if didDetectUserCopyShortcut,
           let currentString,
           !currentString.isEmpty,
           currentString != marker {
            return .externalWrite
        }

        if let currentString, !currentString.isEmpty, currentString != marker {
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
