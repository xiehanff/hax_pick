import AppKit

@MainActor
final class ToolbarPanelController: NSObject, NSWindowDelegate {
    private let toolbarVerticalOffset: CGFloat = 12

    var onDismissSelection: ((String) -> Void)?
    private var panel: HaxPickPanel?
    private var sessionViewModel: PanelSessionViewModel?
    private var rootView: FloatingToolbarView?
    private var currentAnchorPoint: NSPoint = .zero
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func show(text: String, at screenPoint: NSPoint, service: DeepSeekService) {
        currentAnchorPoint = screenPoint

        let viewModel: PanelSessionViewModel
        if let existing = sessionViewModel {
            viewModel = existing
        } else {
            let created = PanelSessionViewModel(service: service) { [weak self] in
                self?.dismissPanel()
            }
            created.onModeChanged = { [weak self] mode in
                self?.modeDidChange(mode)
            }
            sessionViewModel = created
            viewModel = created
        }

        if rootView == nil {
            rootView = FloatingToolbarView(viewModel: viewModel)
        }

        viewModel.reset(with: text)

        let panel = panel ?? buildPanel()
        let size = panelSize(for: viewModel.mode, at: screenPoint)
        panel.setContentSize(size)
        if let rootView {
            rootView.frame = NSRect(origin: .zero, size: size)
            rootView.autoresizingMask = [.width, .height]
            rootView.refreshModeIfNeeded(force: true)
            if panel.contentView !== rootView {
                panel.contentView = rootView
            }
        }
        panel.setFrameOrigin(clampedOrigin(for: screenPoint, mode: viewModel.mode))
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = viewModel.mode == .toolbar
        panel.invalidateShadow()
        present(panel: panel, for: viewModel.mode)
        self.panel = panel
        installKeyMonitorIfNeeded()
        installMouseMonitorIfNeeded()
    }

    private func modeDidChange(_ mode: PanelSessionViewModel.PanelMode) {
        guard let panel else { return }
        let size = panelSize(for: mode, at: currentAnchorPoint)
        panel.setContentSize(size)
        rootView?.frame = NSRect(origin: .zero, size: size)
        rootView?.refreshModeIfNeeded(force: true)
        panel.setFrameOrigin(clampedOrigin(for: currentAnchorPoint, mode: mode))
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = mode == .toolbar
        panel.invalidateShadow()
        present(panel: panel, for: mode)
    }

    private func buildPanel() -> HaxPickPanel {
        let panel = HaxPickPanel(
            contentRect: NSRect(origin: .zero, size: FloatingPanelLayout.toolbarSize),
            // The toolbar is kept non-key by how it is presented, not by making
            // the window a nonactivating panel. Result mode must be a real key
            // window so NSTextView can own the field editor / insertion point.
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.appearance = AppTheme.windowAppearance
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
        panel.hasShadow = true
        panel.delegate = self
        return panel
    }

    private func panelSize(for mode: PanelSessionViewModel.PanelMode, at screenPoint: NSPoint) -> NSSize {
        switch mode {
        case .toolbar:
            return FloatingPanelLayout.toolbarSize
        case .result:
            let visibleFrame = visibleFrame(containing: screenPoint)
            let availableWidth = max(320, visibleFrame.width - FloatingPanelLayout.screenEdgeInset * 2)
            let preferredWidth = visibleFrame.width * FloatingPanelLayout.resultWidthFraction
            let width = min(
                max(preferredWidth, FloatingPanelLayout.resultMinimumWidth),
                min(FloatingPanelLayout.resultMaximumWidth, availableWidth)
            )
            let availableHeight = max(360, visibleFrame.height - FloatingPanelLayout.screenEdgeInset * 2)
            let preferredHeight = visibleFrame.height * FloatingPanelLayout.resultHeightFraction
            let height = min(
                max(preferredHeight, FloatingPanelLayout.resultMinimumHeight),
                min(FloatingPanelLayout.resultMaximumHeight, availableHeight)
            )
            return NSSize(width: width, height: height)
        }
    }

    private func clampedOrigin(for screenPoint: NSPoint, mode: PanelSessionViewModel.PanelMode) -> NSPoint {
        let panelSize = panelSize(for: mode, at: screenPoint)
        let visibleFrame = visibleFrame(containing: screenPoint)

        if mode == .result {
            return NSPoint(
                x: visibleFrame.maxX - panelSize.width - FloatingPanelLayout.screenEdgeInset,
                y: visibleFrame.midY - panelSize.height / 2
            )
        }

        let desiredX = screenPoint.x - (panelSize.width / 2)
        let desiredY = screenPoint.y - panelSize.height - toolbarVerticalOffset

        let minX = visibleFrame.minX + FloatingPanelLayout.screenEdgeInset
        let maxX = visibleFrame.maxX - panelSize.width - FloatingPanelLayout.screenEdgeInset
        let minY = visibleFrame.minY + FloatingPanelLayout.screenEdgeInset
        let maxY = visibleFrame.maxY - panelSize.height - FloatingPanelLayout.screenEdgeInset

        return NSPoint(
            x: min(max(desiredX, minX), maxX),
            y: min(max(desiredY, minY), maxY)
        )
    }

    private func visibleFrame(containing point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
    }

    private func installKeyMonitorIfNeeded() {
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard self?.panel?.isVisible == true else { return event }
                guard event.keyCode == 53 else { return event }
                self?.dismissPanel()
                return nil
            }
        }

        if globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, self?.panel?.isVisible == true else { return }
                self?.dismissPanel()
            }
        }
    }

    private func present(panel: HaxPickPanel, for mode: PanelSessionViewModel.PanelMode) {
        switch mode {
        case .toolbar:
            panel.ignoresMouseEvents = NSEvent.pressedMouseButtons & 1 != 0
            panel.orderFrontRegardless()
        case .result:
            panel.ignoresMouseEvents = false
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func installMouseMonitorIfNeeded() {
        guard globalMouseMonitor == nil else { return }

        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleMouseEvent(event)
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown],
            handler: handler
        )

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard let panel, panel.isVisible else { return }
        guard sessionViewModel?.mode == .toolbar else { return }
        if event.type == .leftMouseUp {
            panel.ignoresMouseEvents = false
            return
        }

        if event.window == panel {
            return
        }

        let screenLocation: NSPoint
        if let window = event.window {
            screenLocation = window.convertPoint(toScreen: event.locationInWindow)
        } else {
            screenLocation = NSEvent.mouseLocation
        }

        guard !panel.frame.contains(screenLocation) else { return }
        dismissPanel()
    }

    private func dismissPanel() {
        if let viewModel = sessionViewModel {
            guard viewModel.prepareForDismissal() else { return }
            if !viewModel.selectedText.isEmpty {
                onDismissSelection?(viewModel.selectedText)
            }
        }
        panel?.close()
    }
}
