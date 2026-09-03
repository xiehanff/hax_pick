import ApplicationServices
import AppKit

struct TextSelectionSnapshot {
    let text: String
    let anchorPoint: NSPoint
}

enum AccessibilityTextService {
    private static let browserFallbackRoles = [
        "AXWebArea",
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
        guard let focusedElement else {
            return nil
        }

        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )

        guard selectedResult == .success, let text = selectedValue as? String else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fallbackPoint = dragStartPoint.midpoint(to: releasePoint)
        let anchorPoint = selectionAnchorPoint(
            for: focusedElement,
            fallbackPoint: fallbackPoint,
            releasePoint: releasePoint
        ) ?? fallbackPoint
        return TextSelectionSnapshot(text: trimmed, anchorPoint: anchorPoint)
    }

    static func shouldAttemptClipboardFallback() -> Bool {
        shouldAttemptClipboardFallback(using: focusedElementSnapshot())
    }

    static func shouldAttemptClipboardFallback(using focusedElement: AXUIElement?) -> Bool {
        guard let focusedElement else { return false }
        return supportsClipboardFallback(on: focusedElement)
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
        var attributeNames: CFArray?
        let result = AXUIElementCopyAttributeNames(focusedElement, &attributeNames)
        guard result == .success, let attributeNames else {
            return false
        }

        let names = (attributeNames as [AnyObject]).compactMap { $0 as? String }
        return shouldUseClipboardFallback(
            attributeNames: names,
            role: role(of: focusedElement)
        )
    }

    static func shouldUseClipboardFallback(attributeNames: [String], role: String? = nil) -> Bool {
        let fallbackCandidates = fallbackAttributeCandidates.map { $0 as String }
        if fallbackCandidates.contains(where: attributeNames.contains) {
            return true
        }

        guard let role else { return false }
        return browserFallbackRoles.contains(role)
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
