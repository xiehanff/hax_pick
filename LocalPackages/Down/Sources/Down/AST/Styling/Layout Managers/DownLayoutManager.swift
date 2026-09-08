//
//  DownLayoutManager.swift
//  Down
//
//  Created by John Nguyen on 02.08.19.
//  Copyright © 2016-2019 Down. All rights reserved.
//

#if !os(watchOS) && !os(Linux)

#if canImport(UIKit)

import UIKit

#elseif canImport(AppKit)

import AppKit

#endif

/// A layout manager capable of drawing the custom attributes set by the `DownStyler`.
///
/// Insert this into a TextKit stack manually, or use the provided `DownTextView`.

public class DownLayoutManager: NSLayoutManager {

    // MARK: - Graphic context

    #if canImport(UIKit)
    var context: CGContext? {
        return UIGraphicsGetCurrentContext()
    }

    func push(context: CGContext) {
        UIGraphicsPushContext(context)
    }

    func popContext() {
        UIGraphicsPopContext()
    }

    #elseif canImport(AppKit)
    var context: CGContext? {
        return NSGraphicsContext.current?.cgContext
    }

    func push(context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
    }

    func popContext() {
        NSGraphicsContext.restoreGraphicsState()
    }

    #endif

    // MARK: - Drawing

    override public func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawCustomBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawCustomAttributes(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawCustomBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let context = context else { return }
        push(context: context)
        defer { popContext() }

        guard let textStorage = textStorage else { return }

        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        textStorage.enumerateAttributes(for: .blockBackgroundColor,
                                        in: characterRange) { (attr: BlockBackgroundColorAttribute, blockRange) in
            let inset = attr.inset

            context.setFillColor(attr.color.cgColor)

            let glyphRange = self.glyphRange(forCharacterRange: blockRange, actualCharacterRange: nil)

            // HaxPick patch: instead of filling one full-bleed rectangle per
            // line (which runs into both container edges with square corners),
            // paint a single rounded card. Horizontal extent comes from the
            // line rects (used rects differ per line and would leave a stepped
            // left edge); vertical extent comes from the used rects (line rects
            // fold paragraphSpacingBefore/After of neighbouring paragraphs in,
            // which would make the card swallow the outer margins and glue
            // itself to the surrounding text).
            var horizontal: (minX: CGFloat, maxX: CGFloat)?
            var vertical: (minY: CGFloat, maxY: CGFloat)?
            enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, lineUsedRect, _, _, _ in
                horizontal = horizontal.map { current in
                    (min(current.minX, lineRect.minX), max(current.maxX, lineRect.maxX))
                } ?? (lineRect.minX, lineRect.maxX)
                vertical = vertical.map { current in
                    (min(current.minY, lineUsedRect.minY), max(current.maxY, lineUsedRect.maxY))
                } ?? (lineUsedRect.minY, lineUsedRect.maxY)
            }

            guard let h = horizontal, let v = vertical else { return }

            // HaxPick patch: extra vertical breathing room so code lines never
            // touch the card edges.
            let verticalPadding = max(10, inset)
            var cardRect = CGRect(
                x: h.minX + inset,
                y: v.minY - verticalPadding,
                width: h.maxX - h.minX - inset * 2,
                height: v.maxY - v.minY + verticalPadding * 2
            )

            if let container = textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil) {
                let minX = container.lineFragmentPadding + inset
                let maxX = container.size.width - inset
                let clampedX = max(cardRect.minX, minX)
                cardRect.origin.x = clampedX
                cardRect.size.width = min(cardRect.width, max(0, maxX - clampedX))
            }

            let radius = min(6, cardRect.width / 2, cardRect.height / 2)
            let path = CGPath(
                roundedRect: cardRect.translated(by: origin),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
        }
    }

    private func drawCustomAttributes(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        drawThematicBreakIfNeeded(in: characterRange, at: origin)
        drawQuoteStripeIfNeeded(in: characterRange, at: origin)
    }

    private func drawThematicBreakIfNeeded(in characterRange: NSRange, at origin: CGPoint) {
        guard let context = context else { return }
        push(context: context)
        defer { popContext() }

        textStorage?.enumerateAttributes(for: .thematicBreak,
                                         in: characterRange) { (attr: ThematicBreakAttribute, range) in

            let firstGlyphIndex = glyphIndexForCharacter(at: range.lowerBound)

            let lineRect = lineFragmentRect(forGlyphAt: firstGlyphIndex, effectiveRange: nil)
            let usedRect = lineFragmentUsedRect(forGlyphAt: firstGlyphIndex, effectiveRange: nil)

            let lineStart = usedRect.minX + fragmentPadding(forGlyphAt: firstGlyphIndex)

            let width = lineRect.width - lineStart
            let height = lineRect.height

            let boundingRect = CGRect(x: lineStart, y: lineRect.minY, width: width, height: height)
            let adjustedLineRect = boundingRect.translated(by: origin)

            drawThematicBreak(with: context, in: adjustedLineRect, attr: attr)
        }
    }

    private func fragmentPadding(forGlyphAt glyphIndex: Int) -> CGFloat {
        let textContainer = self.textContainer(forGlyphAt: glyphIndex, effectiveRange: nil)
        return textContainer?.lineFragmentPadding ?? 0
    }

    private func drawThematicBreak(with context: CGContext, in rect: CGRect, attr: ThematicBreakAttribute) {
        context.setStrokeColor(attr.color.cgColor)
        context.setLineWidth(attr.thickness)
        context.move(to: CGPoint(x: rect.minX, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        context.strokePath()
    }

    private func drawQuoteStripeIfNeeded(in characterRange: NSRange, at origin: CGPoint) {
        guard let context = context else { return }
        push(context: context)
        defer { popContext() }

        textStorage?.enumerateAttributes(for: .quoteStripe,
                                         in: characterRange) { (attr: QuoteStripeAttribute, quoteRange) in

            context.setFillColor(attr.color.cgColor)

            let glyphRangeOfQuote = self.glyphRange(forCharacterRange: quoteRange, actualCharacterRange: nil)

            enumerateLineFragments(forGlyphRange: glyphRangeOfQuote) { lineRect, _, container, _, _ in
                let locations = attr.locations.map {
                    CGPoint(x: $0 + container.lineFragmentPadding, y: 0)
                        .translated(by: lineRect.origin)
                        .translated(by: origin)
                }

                let stripeSize = CGSize(width: attr.thickness, height: lineRect.height)
                self.drawQuoteStripes(with: context, locations: locations, size: stripeSize)
            }
        }
    }

    private func drawQuoteStripes(with context: CGContext, locations: [CGPoint], size: CGSize) {
        locations.forEach {
            let stripeRect = CGRect(origin: $0, size: size)
            context.fill(stripeRect)
        }
    }

    private func glyphRanges(for key: NSAttributedString.Key,
                             in storage: NSTextStorage,
                             inCharacterRange range: NSRange) -> [NSRange] {

        return storage
            .ranges(of: key, in: range)
            .map { self.glyphRange(forCharacterRange: $0, actualCharacterRange: nil) }
            .mergeNeighbors()
    }
}

// MARK: - Helpers

private extension NSRange {

    func overlapsStart(of range: NSRange) -> Bool {
        return lowerBound <= range.lowerBound && upperBound > range.lowerBound
    }

    func overlapsEnd(of range: NSRange) -> Bool {
        return lowerBound < range.upperBound && upperBound >= range.upperBound
    }

}

private extension Array where Element == NSRange {

    func mergeNeighbors() -> [Element] {
        let sorted = self.sorted { $0.lowerBound <= $1.lowerBound }

        let result = sorted.reduce(into: [NSRange]()) { acc, next in
            guard let last = acc.popLast() else {
                acc.append(next)
                return
            }

            guard last.upperBound == next.lowerBound else {
                acc.append(contentsOf: [last, next])
                return
            }

            acc.append(NSRange(location: last.lowerBound, length: next.upperBound - last.lowerBound))
        }

        return result
    }

}

#endif
