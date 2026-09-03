import AppKit
import SwiftUI

@MainActor
final class ToolbarPanelController {
    private let screenEdgeInset: CGFloat = 12
    private let toolbarVerticalOffset: CGFloat = 12
    private let resultVerticalOffset: CGFloat = 8

    var onDismissSelection: ((String) -> Void)?
    private var panel: HaxPickPanel?
    private var sessionViewModel: PanelSessionViewModel?
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func show(text: String, at screenPoint: NSPoint, service: DeepSeekService) {
        let viewModel = sessionViewModel ?? PanelSessionViewModel(service: service) { [weak self] in
            self?.dismissPanel()
        }
        viewModel.onModeChanged = { [weak self] mode in
            guard let self else { return }
            self.panel?.setContentSize(self.panelSize(for: mode))
            self.panel?.setFrameOrigin(self.clampedOrigin(for: screenPoint, mode: mode))
            if let panel = self.panel {
                panel.hidesOnDeactivate = self.shouldHideOnDeactivate(for: mode)
                self.present(panel: panel, for: mode)
            }
        }
        viewModel.reset(with: text)
        sessionViewModel = viewModel
        let panel = panel ?? buildPanel()
        panel.setContentSize(panelSize(for: viewModel.mode))
        panel.contentView = AppTheme.makeClippedHostingView(
            rootView: FloatingToolbarView(viewModel: viewModel),
            size: panelSize(for: viewModel.mode)
        )
        panel.setFrameOrigin(clampedOrigin(for: screenPoint, mode: viewModel.mode))
        panel.hidesOnDeactivate = shouldHideOnDeactivate(for: viewModel.mode)
        present(panel: panel, for: viewModel.mode)
        self.panel = panel
        installKeyMonitorIfNeeded()
        installMouseMonitorIfNeeded()
    }

    private func buildPanel() -> HaxPickPanel {
        let panel = HaxPickPanel(
            contentRect: NSRect(origin: .zero, size: panelSize(for: .toolbar)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "HaxPick"
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
        return panel
    }

    private func panelSize(for mode: PanelSessionViewModel.PanelMode) -> NSSize {
        switch mode {
        case .toolbar:
            return NSSize(width: 320, height: 48)
        case .result:
            return NSSize(width: 436, height: 628)
        }
    }

    private func clampedOrigin(for screenPoint: NSPoint, mode: PanelSessionViewModel.PanelMode) -> NSPoint {
        let panelSize = panelSize(for: mode)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let verticalOffset = mode == .toolbar ? toolbarVerticalOffset : resultVerticalOffset

        let desiredX = screenPoint.x - (panelSize.width / 2)
        let desiredY = screenPoint.y - panelSize.height - verticalOffset

        let minX = visibleFrame.minX + screenEdgeInset
        let maxX = visibleFrame.maxX - panelSize.width - screenEdgeInset
        let minY = visibleFrame.minY + screenEdgeInset
        let maxY = visibleFrame.maxY - panelSize.height - screenEdgeInset

        return NSPoint(
            x: min(max(desiredX, minX), maxX),
            y: min(max(desiredY, minY), maxY)
        )
    }

    private func installKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.panel?.isVisible == true else { return event }
            guard event.keyCode == 53 else { return event }
            self?.dismissPanel()
            return nil
        }
    }

    private func present(panel: HaxPickPanel, for mode: PanelSessionViewModel.PanelMode) {
        switch mode {
        case .toolbar:
            panel.orderFrontRegardless()
        case .result:
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func shouldHideOnDeactivate(for mode: PanelSessionViewModel.PanelMode) -> Bool {
        switch mode {
        case .toolbar:
            return false
        case .result:
            return true
        }
    }

    private func installMouseMonitorIfNeeded() {
        guard globalMouseMonitor == nil else {
            return
        }

        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleMouseEvent(event)
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: handler
        )

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard let panel, panel.isVisible else { return }
        let location = event.locationInWindow

        if event.window == panel {
            return
        }

        let screenLocation: NSPoint
        if let window = event.window {
            screenLocation = window.convertPoint(toScreen: location)
        } else {
            screenLocation = NSEvent.mouseLocation
        }

        guard !panel.frame.contains(screenLocation) else { return }
        dismissPanel()
    }

    private func dismissPanel() {
        if let text = sessionViewModel?.selectedText, !text.isEmpty {
            onDismissSelection?(text)
        }
        panel?.close()
    }
}
