import AppKit

final class AppBrandIconView: NSImageView {
    init(size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        translatesAutoresizingMaskIntoConstraints = false
        image = NSApplication.shared.applicationIconImage
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
