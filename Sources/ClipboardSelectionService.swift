import AppKit

enum ClipboardSelectionService {
    static let simulatedCopyEventTag: Int64 = 0x4841585049434B // "HAXPICK"

    static func selectedTextBySimulatedCopy(
        userCopyShortcutDetected: @escaping (Date) -> Bool = { _ in false }
    ) async -> String? {
        // 通道 2a: CGEvent 模拟 ⌘C
        if let text = await copyViaCGEvent(userCopyShortcutDetected: userCopyShortcutDetected) { return text }
        // 通道 2b: AppleScript 兜底
        return await copyViaAppleScript(userCopyShortcutDetected: userCopyShortcutDetected)
    }

    // MARK: - CGEvent 方案

    private static func copyViaCGEvent(
        userCopyShortcutDetected: @escaping (Date) -> Bool
    ) async -> String? {
        return await performSimulatedCopy(
            using: simulateCommandC,
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
            userCopyShortcutDetected: userCopyShortcutDetected
        )
    }

    // MARK: - 公共复制逻辑

    private static func performSimulatedCopy(
        using copyAction: () -> Void,
        userCopyShortcutDetected: @escaping (Date) -> Bool
    ) async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let marker = "HaxPick-\(UUID().uuidString.prefix(8))"
        let fallbackStartedAt = Date()

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)

        copyAction()
        let result = await waitForPasteboardResult(
            pasteboard: pasteboard,
            marker: marker,
            fallbackStartedAt: fallbackStartedAt,
            userCopyShortcutDetected: userCopyShortcutDetected
        )

        switch result {
        case .copiedText(let text):
            snapshot.restore(to: pasteboard)
            return text
        case .timedOut:
            snapshot.restore(to: pasteboard)
            return nil
        case .externalWrite:
            return nil
        }
    }

    private static func waitForPasteboardResult(
        pasteboard: NSPasteboard,
        marker: String,
        fallbackStartedAt: Date,
        userCopyShortcutDetected: @escaping (Date) -> Bool
    ) async -> PasteboardCopyResult {
        let deadline = Date().addingTimeInterval(0.4)

        while Date() < deadline {
            let currentString = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let didChangeExternally = pasteboard.changeCount > 0
            let didDetectUserCopyShortcut = userCopyShortcutDetected(fallbackStartedAt)

            if let result = classifyPasteboardObservation(
                currentString: currentString,
                marker: marker,
                didChangeExternally: didChangeExternally,
                didDetectUserCopyShortcut: didDetectUserCopyShortcut
            ) {
                return result
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        return .timedOut
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
}

enum PasteboardCopyResult: Equatable {
    case copiedText(String)
    case externalWrite
    case timedOut
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
