import SwiftUI

@main
struct HaxPickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    private var trayIcon: NSImage {
        // Load the 32px representation explicitly and give it a 16pt logical size.
        // This keeps the status item crisp on Retina while still downsampling cleanly
        // on a 1x display instead of relying on a separately discovered @2x sibling.
        guard let path = Bundle.main.path(forResource: "MenuBarIcon@2x", ofType: "png"),
              let image = NSImage(contentsOfFile: path) else {
            return NSImage(systemSymbolName: "text.cursor", accessibilityDescription: nil) ?? NSImage()
        }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            Image(nsImage: trayIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
