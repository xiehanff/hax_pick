import SwiftUI

struct AppBrandIcon: View {
    let size: CGFloat

    var body: some View {
        if let image = iconImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private var iconImage: NSImage? {
        guard let path = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
              let image = NSImage(contentsOfFile: path) else {
            return nil
        }
        return image
    }
}
