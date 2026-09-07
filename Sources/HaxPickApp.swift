import AppKit

@main
@MainActor
enum HaxPickApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.appearance = AppTheme.windowAppearance
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}