import ApplicationServices
import AppKit

@MainActor
final class SelectionMonitor {
    private static let minimumSelectionDragDistance: CGFloat = 8

    private let onSelectionDetected: (TextSelectionSnapshot) -> Void
    private let onSelectionMissed: () -> Void
    private let focusedElementSnapshotProvider: () -> AXUIElement?
    private let accessibilitySnapshotProvider: (AXUIElement?, NSPoint, NSPoint) -> TextSelectionSnapshot?
    private let shouldAttemptClipboardFallbackProvider: (AXUIElement?) -> Bool
    private let clipboardFallbackProvider: () async -> String?
    private var mouseMonitor: Any?
    private var mouseDownMonitor: Any?
    private var commandCopyMonitor: Any?
    private var lastSelection = ""
    private var lastTriggerTime = Date.distantPast
    private var ignoredSelection: String?
    private var mouseDownLocation: NSPoint?

    init(
        onSelectionDetected: @escaping (TextSelectionSnapshot) -> Void,
        onSelectionMissed: @escaping () -> Void,
        focusedElementSnapshotProvider: @escaping () -> AXUIElement? = AccessibilityTextService.focusedElementSnapshot,
        accessibilitySnapshotProvider: @escaping (AXUIElement?, NSPoint, NSPoint) -> TextSelectionSnapshot? = AccessibilityTextService.selectedTextSnapshot,
        shouldAttemptClipboardFallbackProvider: @escaping (AXUIElement?) -> Bool = AccessibilityTextService.shouldAttemptClipboardFallback,
        clipboardFallbackProvider: @escaping () async -> String? = {
            await ClipboardSelectionService.selectedTextBySimulatedCopy(
                userCopyShortcutDetected: UserCopyShortcutTracker.shared.didDetectUserCopyShortcut
            )
        }
    ) {
        self.onSelectionDetected = onSelectionDetected
        self.onSelectionMissed = onSelectionMissed
        self.focusedElementSnapshotProvider = focusedElementSnapshotProvider
        self.accessibilitySnapshotProvider = accessibilitySnapshotProvider
        self.shouldAttemptClipboardFallbackProvider = shouldAttemptClipboardFallbackProvider
        self.clipboardFallbackProvider = clipboardFallbackProvider
    }

    func start() {
        guard mouseMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.mouseDownLocation = NSEvent.mouseLocation
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            let mouseUpLocation = NSEvent.mouseLocation
            self?.handleMouseUp(releasePoint: mouseUpLocation)
        }
        commandCopyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            UserCopyShortcutTracker.shared.recordIfNeeded(event: event)
        }
    }

    func stop() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        if let monitor = commandCopyMonitor {
            NSEvent.removeMonitor(monitor)
            commandCopyMonitor = nil
        }
    }

    func ignoreCurrentSelection(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        ignoredSelection = trimmed.isEmpty ? nil : trimmed
    }

    private func handleMouseUp(releasePoint: NSPoint) {
        guard let dragStartPoint = selectionDragStartPoint(releasePoint: releasePoint) else { return }
        let focusedElementSnapshot = focusedElementSnapshotProvider()
        let earlyAccessibilitySnapshot = accessibilitySnapshotProvider(
            focusedElementSnapshot,
            dragStartPoint,
            releasePoint
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }
            self.resetIgnoredSelectionIfNeeded(dragStartPoint: dragStartPoint, releasePoint: releasePoint)

            if let snapshot = await self.resolveSelectionSnapshot(
                earlyAccessibilitySnapshot: earlyAccessibilitySnapshot,
                focusedElement: focusedElementSnapshot,
                dragStartPoint: dragStartPoint,
                releasePoint: releasePoint
            ) {
                self.consume(snapshot: snapshot)
                return
            }

            self.onSelectionMissed()
        }
    }

    func resolveSelectionSnapshot(
        earlyAccessibilitySnapshot: TextSelectionSnapshot? = nil,
        focusedElement: AXUIElement? = nil,
        dragStartPoint: NSPoint,
        releasePoint: NSPoint
    ) async -> TextSelectionSnapshot? {
        // 通道一：AX API（快速重试 1 次，共约 80ms）
        for i in 0..<2 {
            if let snap = accessibilitySnapshotProvider(focusedElement, dragStartPoint, releasePoint) {
                return snap
            }
            if i < 1 {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }

        // 通道二：⌘C 兜底
        guard shouldAttemptClipboardFallbackProvider(focusedElement) else {
            return earlyAccessibilitySnapshot
        }

        if let text = await clipboardFallbackProvider() {
            return TextSelectionSnapshot(
                text: text,
                anchorPoint: dragStartPoint.midpoint(to: releasePoint)
            )
        }

        return earlyAccessibilitySnapshot
    }

    private func consume(snapshot: TextSelectionSnapshot) {
        if let ignoredSelection {
            if snapshot.text == ignoredSelection {
                return
            }
            self.ignoredSelection = nil
        }

        let now = Date()
        if snapshot.text == lastSelection, now.timeIntervalSince(lastTriggerTime) < 1.2 {
            return
        }

        lastSelection = snapshot.text
        lastTriggerTime = now
        onSelectionDetected(snapshot)
    }

    private func resetIgnoredSelectionIfNeeded(dragStartPoint: NSPoint, releasePoint: NSPoint) {
        guard ignoredSelection != nil else { return }
        if dragStartPoint.distance(to: releasePoint) >= Self.minimumSelectionDragDistance {
            ignoredSelection = nil
        }
    }

    private func selectionDragStartPoint(releasePoint: NSPoint) -> NSPoint? {
        guard let mouseDownLocation else { return nil }
        let didDrag = mouseDownLocation.distance(to: releasePoint) >= Self.minimumSelectionDragDistance
        self.mouseDownLocation = nil
        return didDrag ? mouseDownLocation : nil
    }
}

private final class UserCopyShortcutTracker {
    static let shared = UserCopyShortcutTracker()

    private var lastDetectedAt = Date.distantPast

    func recordIfNeeded(event: NSEvent) {
        guard event.type == .keyDown else { return }
        guard event.charactersIgnoringModifiers?.lowercased() == "c" else { return }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else { return }
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ClipboardSelectionService.simulatedCopyEventTag {
            return
        }
        lastDetectedAt = Date()
    }

    func didDetectUserCopyShortcut(since startDate: Date) -> Bool {
        lastDetectedAt >= startDate
    }
}
