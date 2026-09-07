import SwiftUI

@main
struct HaxPickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    private var trayIcon: NSImage {
        // Load the 32px monochrome brand mark explicitly and give it a 16pt logical
        // size. Template rendering lets macOS adapt it to light/dark menu bars.
        guard let path = Bundle.main.path(forResource: "MenuBarIcon@2x", ofType: "png"),
              let image = NSImage(contentsOfFile: path) else {
            return NSImage(systemSymbolName: "text.cursor", accessibilityDescription: nil) ?? NSImage()
        }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }

    var body: some Scene {
        MenuBarExtra {
            SettingsMenuButton()
            Divider()
            Button("退出 HaxPick") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(nsImage: trayIcon)
        }
        .menuBarExtraStyle(.menu)

        Window("HaxPick 设置", id: "haxpick-settings") {
            SettingsContentView(appState: appState)
                .frame(width: 340)
        }
    }
}

private struct SettingsMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("设置…") {
            openWindow(id: "haxpick-settings")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
