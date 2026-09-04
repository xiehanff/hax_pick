import AppKit
import SwiftUI

enum HaxIconAsset: String, CaseIterable {
    case copy = "copy-01-stroke-rounded"
    case refresh = "refresh-01-stroke-rounded"
    case send = "send-stroke-rounded"

    var image: NSImage {
        HaxIconImageStore.images[self] ?? NSImage()
    }
}

struct HaxIcon: View {
    let asset: HaxIconAsset

    var body: some View {
        Image(nsImage: asset.image)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
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
