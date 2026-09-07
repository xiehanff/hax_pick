import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = AppTheme.windowAppearance
        configureStatusItem()
        AppState.shared.start()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = trayIcon
            button.imagePosition = .imageOnly
            button.toolTip = "HaxPick"
        }

        let menu = NSMenu()
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 HaxPick", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private var trayIcon: NSImage {
        guard let path = Bundle.main.path(forResource: "MenuBarIcon@2x", ofType: "png"),
              let image = NSImage(contentsOfFile: path) else {
            return NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "HaxPick") ?? NSImage()
        }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }

    @objc private func openSettings() {
        let controller: SettingsWindowController
        if let existing = settingsWindowController {
            controller = existing
        } else {
            let created = SettingsWindowController(appState: AppState.shared)
            settingsWindowController = created
            controller = created
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.appearance = AppTheme.windowAppearance
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}