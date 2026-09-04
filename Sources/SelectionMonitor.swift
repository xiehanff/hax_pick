import ApplicationServices
import AppKit

@MainActor
final class SelectionMonitor {
    private static let minimumSelectionDragDistance: CGFloat = 3
    private static let dragRetryDelayNanoseconds: UInt64 = 35_000_000

    private let onSelectionDetected: (TextSelectionSnapshot) -> Void
    private let onSelectionMissed: () -> Void
    private let focusedElementSnapshotProvider: () -> AXUIElement?
    private let accessibilitySnapshotProvider: (AXUIElement?, NSPoint, NSPoint) -> TextSelectionSnapshot?
    private let shouldAttemptClipboardFallbackProvider: (AXUIElement?, NSPoint) -> Bool
    private let clipboardFallbackProvider: () async -> String?
    private let earlyClipboardFallbackProvider: () async -> String?

    private var mouseUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var commandCopyMonitor: Any?
    private var dragProbeTask: Task<Void, Never>?
    private var lastSelection = ""
    private var lastTriggerTime = Date.distantPast
    private var ignoredSelection: String?
    private var mouseDownLocation: NSPoint?
    private var mouseDownFocusedElement: AXUIElement?
    private var dragGeneration = 0
    private var hasCrossedSelectionThreshold = false
    private var didPublishDuringCurrentDrag = false

    init(
        onSelectionDetected: @escaping (TextSelectionSnapshot) -> Void,
        onSelectionMissed: @escaping () -> Void,
        focusedElementSnapshotProvider: @escaping () -> AXUIElement? = AccessibilityTextService.focusedElementSnapshot,
        accessibilitySnapshotProvider: @escaping (AXUIElement?, NSPoint, NSPoint) -> TextSelectionSnapshot? = AccessibilityTextService.selectedTextSnapshot,
        shouldAttemptClipboardFallbackProvider: @escaping (AXUIElement?, NSPoint) -> Bool = { element, point in
            AccessibilityTextService.shouldAttemptClipboardFallback(using: element, at: point)
        },
        clipboardFallbackProvider: @escaping () async -> String? = {
            await ClipboardSelectionService.selectedTextBySimulatedCopy(
                userCopyShortcutDetected: UserCopyShortcutTracker.shared.didDetectUserCopyShortcut
            )
        },
        earlyClipboardFallbackProvider: (() async -> String?)? = nil
    ) {
        self.onSelectionDetected = onSelectionDetected
        self.onSelectionMissed = onSelectionMissed
        self.focusedElementSnapshotProvider = focusedElementSnapshotProvider
        self.accessibilitySnapshotProvider = accessibilitySnapshotProvider
        self.shouldAttemptClipboardFallbackProvider = shouldAttemptClipboardFallbackProvider
        self.clipboardFallbackProvider = clipboardFallbackProvider
        self.earlyClipboardFallbackProvider = earlyClipboardFallbackProvider ?? {
            await ClipboardSelectionService.selectedTextBySimulatedCopy(
                allowAppleScriptFallback: false,
                timeout: 0.16,
                userCopyShortcutDetected: UserCopyShortcutTracker.shared.didDetectUserCopyShortcut
            )
        }
    }

    func start() {
        guard mouseUpMonitor == nil else { return }

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.handleMouseDown(at: NSEvent.mouseLocation)
        }
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.handleMouseDragged(to: NSEvent.mouseLocation)
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.handleMouseUp(releasePoint: NSEvent.mouseLocation)
        }
        commandCopyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            UserCopyShortcutTracker.shared.recordIfNeeded(event: event)
        }
    }

    func stop() {
        for monitor in [mouseUpMonitor, mouseDownMonitor, mouseDraggedMonitor, commandCopyMonitor] {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseUpMonitor = nil
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        commandCopyMonitor = nil
        dragProbeTask?.cancel()
        dragProbeTask = nil
        mouseDownLocation = nil
        mouseDownFocusedElement = nil
    }

    func ignoreCurrentSelection(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        ignoredSelection = trimmed.isEmpty ? nil : trimmed
    }

    func handleMouseDown(at point: NSPoint) {
        dragGeneration += 1
        dragProbeTask?.cancel()
        dragProbeTask = nil
        mouseDownLocation = point
        mouseDownFocusedElement = focusedElementSnapshotProvider()
        hasCrossedSelectionThreshold = false
        didPublishDuringCurrentDrag = false
    }

    func handleMouseDragged(to currentPoint: NSPoint) {
        guard let dragStartPoint = mouseDownLocation else { return }
        guard dragStartPoint.distance(to: currentPoint) >= Self.minimumSelectionDragDistance else { return }

        markCurrentDragAsSelectionGesture()
        guard !didPublishDuringCurrentDrag, dragProbeTask == nil else { return }

        let focusedElement = mouseDownFocusedElement ?? focusedElementSnapshotProvider()
        if let snapshot = accessibilitySnapshotProvider(focusedElement, dragStartPoint, currentPoint) {
            didPublishDuringCurrentDrag = consume(snapshot: snapshot)
            return
        }

        let generation = dragGeneration
        dragProbeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.resolveSelectionDuringDrag(
                focusedElement: focusedElement,
                dragStartPoint: dragStartPoint,
                currentPoint: currentPoint
            )
            guard !Task.isCancelled else { return }
            self.dragProbeTask = nil
            guard self.dragGeneration == generation, self.mouseDownLocation != nil else { return }
            guard let snapshot else { return }
            self.didPublishDuringCurrentDrag = self.consume(snapshot: snapshot)
        }
    }

    func resolveSelectionDuringDrag(
        focusedElement: AXUIElement?,
        dragStartPoint: NSPoint,
        currentPoint: NSPoint
    ) async -> TextSelectionSnapshot? {
        do {
            try await Task.sleep(nanoseconds: Self.dragRetryDelayNanoseconds)
        } catch {
            return nil
        }

        if let snapshot = accessibilitySnapshotProvider(focusedElement, dragStartPoint, currentPoint) {
            return snapshot
        }

        guard shouldAttemptClipboardFallbackProvider(focusedElement, currentPoint) else {
            return nil
        }
        guard let text = await earlyClipboardFallbackProvider() else {
            return nil
        }
        return TextSelectionSnapshot(
            text: text,
            anchorPoint: dragStartPoint.midpoint(to: currentPoint)
        )
    }

    func handleMouseUp(releasePoint: NSPoint) {
        guard let dragStartPoint = mouseDownLocation else { return }
        let didDrag = dragStartPoint.distance(to: releasePoint) >= Self.minimumSelectionDragDistance
        let focusedElement = mouseDownFocusedElement ?? focusedElementSnapshotProvider()
        let generation = dragGeneration
        let publishedDuringDrag = didPublishDuringCurrentDrag
        let pendingProbe = dragProbeTask

        if didDrag {
            markCurrentDragAsSelectionGesture()
        }
        mouseDownLocation = nil
        mouseDownFocusedElement = nil
        dragProbeTask = nil
        pendingProbe?.cancel()

        guard didDrag else { return }
        let earlyAccessibilitySnapshot = accessibilitySnapshotProvider(
            focusedElement,
            dragStartPoint,
            releasePoint
        )

        Task { @MainActor [weak self] in
            if let pendingProbe {
                await pendingProbe.value
            }
            guard let self, self.dragGeneration == generation else { return }

            do {
                try await Task.sleep(nanoseconds: Self.dragRetryDelayNanoseconds)
            } catch {
                return
            }

            if let snapshot = await self.resolveSelectionSnapshot(
                earlyAccessibilitySnapshot: earlyAccessibilitySnapshot,
                focusedElement: focusedElement,
                dragStartPoint: dragStartPoint,
                releasePoint: releasePoint
            ) {
                self.consume(snapshot: snapshot)
                return
            }

            if !publishedDuringDrag {
                self.onSelectionMissed()
            }
        }
    }

    func resolveSelectionSnapshot(
        earlyAccessibilitySnapshot: TextSelectionSnapshot? = nil,
        focusedElement: AXUIElement? = nil,
        dragStartPoint: NSPoint,
        releasePoint: NSPoint
    ) async -> TextSelectionSnapshot? {
        // 通道一：AX API（快速重试 1 次，共约 80ms）
        for index in 0..<2 {
            if let snapshot = accessibilitySnapshotProvider(focusedElement, dragStartPoint, releasePoint) {
                return snapshot
            }
            if index == 0 {
                do {
                    try await Task.sleep(nanoseconds: 80_000_000)
                } catch {
                    return earlyAccessibilitySnapshot
                }
            }
        }

        // 通道二：在焦点元素或鼠标下方的文本层级上模拟 ⌘C。
        guard shouldAttemptClipboardFallbackProvider(focusedElement, releasePoint) else {
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

    @discardableResult
    private func consume(snapshot: TextSelectionSnapshot) -> Bool {
        let text = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        if let ignoredSelection {
            if text == ignoredSelection {
                return false
            }
            self.ignoredSelection = nil
        }

        let now = Date()
        if text == lastSelection, now.timeIntervalSince(lastTriggerTime) < 1.2 {
            return false
        }

        lastSelection = text
        lastTriggerTime = now
        onSelectionDetected(TextSelectionSnapshot(text: text, anchorPoint: snapshot.anchorPoint))
        return true
    }

    private func markCurrentDragAsSelectionGesture() {
        guard !hasCrossedSelectionThreshold else { return }
        hasCrossedSelectionThreshold = true
        ignoredSelection = nil
        lastTriggerTime = .distantPast
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
