import ApplicationServices
import AppKit

struct TextSelectionSnapshot {
    let text: String
    let anchorPoint: NSPoint
}

enum AccessibilityTextService {
    private static let clipboardFallbackRoles = [
        "AXWebArea",
        "AXStaticText",
        "AXTextArea",
        "AXTextField",
    ]

    private static let textSelectionApplicationIdentifiers = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.microsoft.VSCode",
        "com.openai.codex",
        "com.tencent.qqbrowser",
        "com.apple.dt.Xcode",
        "org.mozilla.firefox",
        "org.jetbrains.",
        "com.jetbrains.",
        "cn.trae.app",
        "dev.zcode.app",
    ]

    private static let fallbackAttributeCandidates: [CFString] = [
        kAXSelectedTextAttribute as CFString,
        kAXSelectedTextRangeAttribute as CFString,
        kAXNumberOfCharactersAttribute as CFString,
    ]

    static func selectedTextSnapshot(dragStartPoint: NSPoint, releasePoint: NSPoint) -> TextSelectionSnapshot? {
        let focusedElement = focusedElementSnapshot()
        return selectedTextSnapshot(
            from: focusedElement,
            dragStartPoint: dragStartPoint,
            releasePoint: releasePoint
        )
    }

    static func selectedTextSnapshot(
        from focusedElement: AXUIElement?,
        dragStartPoint: NSPoint,
        releasePoint: NSPoint
    ) -> TextSelectionSnapshot? {
        let fallbackPoint = dragStartPoint.midpoint(to: releasePoint)
        for element in selectionCandidateElements(
            focusedElement: focusedElement,
            dragStartPoint: dragStartPoint,
            releasePoint: releasePoint
        ) {
            guard let text = selectedText(from: element) else { continue }
            let anchorPoint = selectionAnchorPoint(
                for: element,
                fallbackPoint: fallbackPoint,
                releasePoint: releasePoint
            ) ?? fallbackPoint
            return TextSelectionSnapshot(text: text, anchorPoint: anchorPoint)
        }
        return nil
    }

    static func shouldAttemptClipboardFallback() -> Bool {
        shouldAttemptClipboardFallback(
            using: focusedElementSnapshot(),
            at: NSEvent.mouseLocation
        )
    }

    static func shouldAttemptClipboardFallback(
        using focusedElement: AXUIElement?,
        at screenPoint: NSPoint = NSEvent.mouseLocation
    ) -> Bool {
        let candidates = selectionCandidateElements(
            focusedElement: focusedElement,
            dragStartPoint: screenPoint,
            releasePoint: screenPoint
        )
        if candidates.contains(where: supportsClipboardFallback) {
            return true
        }

        guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return isKnownTextSelectionApplication(bundleIdentifier: bundleIdentifier)
    }

    static func isKnownTextSelectionApplication(bundleIdentifier: String) -> Bool {
        textSelectionApplicationIdentifiers.contains {
            bundleIdentifier == $0 || bundleIdentifier.hasPrefix($0)
        }
    }

    static func focusedElementSnapshot() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        return focusedElement(from: systemWideElement)
    }

    private static func focusedElement(from systemWideElement: AXUIElement) -> AXUIElement? {
        var focusedObject: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )

        guard focusedResult == .success, let element = focusedObject else {
            return nil
        }
        return (element as! AXUIElement)
    }

    private static func selectionAnchorPoint(
        for focusedElement: AXUIElement,
        fallbackPoint: NSPoint,
        releasePoint: NSPoint
    ) -> NSPoint? {
        guard let selectedRangeValue = selectedTextRange(from: focusedElement),
              let selectedBounds = bounds(for: selectedRangeValue, focusedElement: focusedElement) else {
            return nil
        }

        let rawAnchor = NSPoint(x: selectedBounds.midX, y: selectedBounds.minY)
        var candidates = [rawAnchor]

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(fallbackPoint) }) ?? NSScreen.main {
            let flippedMaxY = screen.frame.maxY - selectedBounds.minY
            let flippedMinY = flippedMaxY - selectedBounds.height
            candidates.append(NSPoint(x: selectedBounds.midX, y: flippedMinY))
        }

        let bestCandidate = candidates.min { lhs, rhs in
            lhs.distance(to: fallbackPoint) < rhs.distance(to: fallbackPoint)
        }

        guard let bestCandidate else { return nil }
        guard isReasonableAnchor(bestCandidate, comparedTo: fallbackPoint, releasePoint: releasePoint) else {
            return nil
        }
        return bestCandidate
    }

    private static func selectedTextRange(from focusedElement: AXUIElement) -> AXValue? {
        var rangeValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )

        guard result == .success, let value = rangeValue else {
            return nil
        }
        return (value as! AXValue)
    }

    private static func bounds(for rangeValue: AXValue, focusedElement: AXUIElement) -> CGRect? {
        var parameterizedValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &parameterizedValue
        )

        guard result == .success,
              let axValue = parameterizedValue,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let value = axValue as! AXValue
        guard AXValueGetType(value) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        let success = AXValueGetValue(value, .cgRect, &rect)
        return success ? rect : nil
    }

    private static func supportsClipboardFallback(on focusedElement: AXUIElement) -> Bool {
        let elementRole = role(of: focusedElement)
        if elementRole.map(clipboardFallbackRoles.contains) == true {
            return true
        }

        var attributeNames: CFArray?
        let result = AXUIElementCopyAttributeNames(focusedElement, &attributeNames)
        guard result == .success, let attributeNames else {
            return false
        }

        let names = (attributeNames as [AnyObject]).compactMap { $0 as? String }
        return shouldUseClipboardFallback(
            attributeNames: names,
            role: elementRole
        )
    }

    static func shouldUseClipboardFallback(attributeNames: [String], role: String? = nil) -> Bool {
        let fallbackCandidates = fallbackAttributeCandidates.map { $0 as String }
        if fallbackCandidates.contains(where: attributeNames.contains) {
            return true
        }

        guard let role else { return false }
        return clipboardFallbackRoles.contains(role)
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard result == .success, let text = selectedValue as? String else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func selectionCandidateElements(
        focusedElement: AXUIElement?,
        dragStartPoint: NSPoint,
        releasePoint: NSPoint
    ) -> [AXUIElement] {
        var candidates: [AXUIElement] = []

        func appendHierarchy(startingAt element: AXUIElement?) {
            var current = element
            for _ in 0..<8 {
                guard let element = current else { return }
                if !candidates.contains(where: { CFEqual($0, element) }) {
                    candidates.append(element)
                }
                current = parent(of: element)
            }
        }

        appendHierarchy(startingAt: element(atAppKitScreenPoint: releasePoint))
        appendHierarchy(startingAt: element(atAppKitScreenPoint: dragStartPoint))
        appendHierarchy(startingAt: focusedElement)
        return candidates
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var parentValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentValue
        )
        guard result == .success,
              let parentValue,
              CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return (parentValue as! AXUIElement)
    }

    private static func element(atAppKitScreenPoint point: NSPoint) -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let candidatePoints = [
            NSPoint(x: point.x, y: primaryMaxY - point.y),
            point,
        ]

        for candidatePoint in candidatePoints {
            var element: AXUIElement?
            let result = AXUIElementCopyElementAtPosition(
                systemWideElement,
                Float(candidatePoint.x),
                Float(candidatePoint.y),
                &element
            )
            if result == .success, let element {
                return element
            }
        }
        return nil
    }

    private static func role(of element: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )

        guard result == .success, let role = roleValue as? String else {
            return nil
        }
        return role
    }

    private static func isReasonableAnchor(_ candidate: NSPoint, comparedTo fallbackPoint: NSPoint, releasePoint: NSPoint) -> Bool {
        let distanceToFallback = candidate.distance(to: fallbackPoint)
        let distanceToRelease = candidate.distance(to: releasePoint)
        return distanceToFallback <= 260 && distanceToRelease <= 320
    }
}
