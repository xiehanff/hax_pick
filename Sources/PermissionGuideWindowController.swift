import AppKit
import SwiftUI

@MainActor
final class PermissionGuideWindowController: NSObject, NSWindowDelegate {
    private static let hasShownKey = "permission_guide_seen"
    private static let panelSize = NSSize(width: 480, height: 420)

    private weak var appState: AppState?
    private var panel: HaxPickPanel?

    init(appState: AppState) {
        self.appState = appState
    }

    func presentIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasShownKey) else { return }
        present()
    }

    func present() {
        if panel?.isVisible == true {
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PermissionGuideView(
            appState: appState ?? AppState.shared,
            onClose: { [weak self] in self?.dismiss() }
        )
        let contentView = AppTheme.makeHostingView(
            rootView: view,
            size: Self.panelSize
        )

        let panel = HaxPickPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.title = "HaxPick 权限引导"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = contentView
        panel.center()

        self.panel = panel
        UserDefaults.standard.set(true, forKey: Self.hasShownKey)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func syncVisibility(permissionGranted: Bool) {
        guard permissionGranted else { return }
        dismiss()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}
