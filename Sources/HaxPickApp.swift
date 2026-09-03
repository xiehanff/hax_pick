import SwiftUI

@main
struct HaxPickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    private var trayIcon: NSImage {
        guard let path = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
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
