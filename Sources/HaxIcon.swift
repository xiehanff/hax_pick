import AppKit

enum HaxIconAsset: String, CaseIterable {
    case copy = "copy-01-stroke-rounded"
    case refresh = "refresh-01-stroke-rounded"
    case send = "send-stroke-rounded"

    var image: NSImage {
        HaxIconImageStore.images[self] ?? NSImage()
    }
}

final class HaxIconImageView: NSImageView {
    init(asset: HaxIconAsset, size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        translatesAutoresizingMaskIntoConstraints = false
        image = asset.image
        imageScaling = .scaleProportionallyUpOrDown
        contentTintColor = AppTheme.textPrimary
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private enum HaxIconImageStore {
    static let images = Dictionary(
        uniqueKeysWithValues: HaxIconAsset.allCases.map { asset in
            (asset, load(asset))
        }
    )

    private static func load(_ asset: HaxIconAsset) -> NSImage {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle.main
#endif
        guard
            let url = bundle.url(
                forResource: asset.rawValue,
                withExtension: "svg",
                subdirectory: "HaxIcons"
            ),
            let image = NSImage(contentsOf: url)
        else {
            return NSImage()
        }

        image.isTemplate = true
        return image
    }
}
