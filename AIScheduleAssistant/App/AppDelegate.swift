import AppKit
import SwiftUI

@MainActor class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var windows: [String: NSWindow] = [:]
    private let navigation = SettingsNavigation()
    private var menuNavigation = MenuNavigation()
    private var sessions: [UUID: ContentProcessViewModel] = [:]
    private var savingWorkers: [UUID: ContentProcessViewModel] = [:]
    private var deferredPresentations: [(ContentProcessViewModel, Bool)] = []
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var menuTracking = false
    private var popoverSession = UUID()
    lazy var queue = RecognitionQueue()
    // The fixture editor is isolated from production recognition jobs.
    lazy var viewModel = ContentProcessViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = (NSImage(named: "MenuBarIcon") ?? NSImage(named: "MiloIcon"))?.copy() as? NSImage
            image?.isTemplate = false; image?.size = NSSize(width: 18, height: 18)
            button.image = image; button.imageScaling = .scaleProportionallyDown
            button.isBordered = false
            button.sendAction(on: .leftMouseUp)
            button.wantsLayer = true; button.layer?.masksToBounds = true
            button.toolTip = miloWindowTitle; button.action = #selector(togglePopover); button.target = self
            button.setAccessibilityLabel(miloWindowTitle)
        }
        queue.onWorkerCreated = { [weak self] worker in self?.configure(worker) }
        queue.onReady = { [weak self] worker in self?.present(worker, error: false) }
        queue.onFailure = { [weak self] worker in self?.present(worker, error: true) }
        queue.onCaptureEnded = { [weak self] in
            guard let self else { return }
            let items = deferredPresentations; deferredPresentations.removeAll()
            for (worker, error) in items { present(worker, error: error) }
        }
        if RuntimeMode.isPreview {
            #if DEBUG
            MiloFixtures.installGlassBackdrop()
            #endif
            configure(viewModel); MiloFixtures.install(viewModel: viewModel); showPreviewWindow()
        } else if !UserDefaults.standard.bool(forKey: "hasShownWelcome") {
            showWelcomeWindow(); UserDefaults.standard.set(true, forKey: "hasShownWelcome")
        }
    }
    @objc func togglePopover() {
        if popover?.isShown == true { closePopover() } else { openPopover() }
    }
    private func openPopover(composing: Bool = false) {
        guard let button = statusItem?.button else { return }
        if let current = popover, current.isShown {
            if composing { menuNavigation.composing = true }
            current.contentViewController?.view.window?.makeKey(); return
        }
        // Every presentation gets a new native popover and SwiftUI control tree.
        menuNavigation = MenuNavigation(); menuNavigation.composing = composing
        popoverSession = UUID()
        let menu = NSPopover(); menu.behavior = .applicationDefined; menu.animates = false; menu.delegate = self
        popover = menu
        menu.contentViewController = NSHostingController(rootView: MenuBarView(appDelegate: self, queue: queue, navigation: menuNavigation, presentationID: popoverSession).preferredColorScheme(.light))
        NSApp.unhideWithoutActivation(); NSApp.activate(ignoringOtherApps: true)
        menu.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        menu.contentViewController?.view.window?.makeKey()
        installPopoverMonitors()
    }
    func resizePopover(_ size: CGSize, session: UUID) {
        guard popoverSession == session, size.width > 0, size.height > 0, let popover else { return }
        let measured = NSSize(width: ceil(size.width), height: ceil(size.height))
        if popover.contentSize != measured { popover.contentSize = measured }
    }
    func closePopover() {
        removePopoverMonitors(); popoverSession = UUID()
        guard let current = popover else { return }
        current.performClose(nil)
        statusItem?.button?.highlight(false)
        releaseClosedPopover(current)
    }
    func popoverDidClose(_ notification: Notification) {
        guard let current = notification.object as? NSPopover, current === popover else { return }
        removePopoverMonitors(); popoverSession = UUID()
        statusItem?.button?.highlight(false)
        releaseClosedPopover(current)
    }
    private func releaseClosedPopover(_ current: NSPopover) {
        // Let the mouse-up action finish before disposing its control tree.
        DispatchQueue.main.async { [weak self, weak current] in
            guard let self, let current, current === popover, !current.isShown else { return }
            current.contentViewController = nil; popover = nil; menuNavigation = MenuNavigation()
        }
    }
    private func dismissPopover(session: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, popoverSession == session, popover?.isShown == true else { return }
            closePopover()
        }
    }
    private func installPopoverMonitors() {
        removePopoverMonitors()
        let session = popoverSession
        let outside: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mouseUp: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseUp.union(.keyDown)) { [weak self] event in
            guard let self, popoverSession == session, popover?.isShown == true else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 && !menuTracking { dismissPopover(session: session); return nil }
                return event
            }
            if event.window === statusItem?.button?.window || menuTracking { return event }
            if let window = event.window, window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue { return event }
            var owner = event.window
            while let window = owner {
                if window === popover?.contentViewController?.view.window { return event }
                owner = window.parent
            }
            // SwiftUI/AppKit child controls can report an auxiliary or nil event.window.
            if let window = popover?.contentViewController?.view.window, window.frame.contains(NSEvent.mouseLocation) { return event }
            dismissPopover(session: session); return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: outside) { [weak self] _ in
            Task { @MainActor in self?.dismissPopover(session: session) }
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !NSApp.isActive, !self.menuTracking else { return }
                self.dismissPopover(session: session)
            }
        }
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTracking = true }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.menuTracking = false
                    if !NSApp.isActive { self?.dismissPopover(session: session) }
                }
            }
        ]
    }
    private func removePopoverMonitors() {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor); self.localClickMonitor = nil }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor); self.globalClickMonitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers.removeAll(); menuTracking = false
    }
    func beginScreenshot() {
        guard !queue.isCapturing else { return }
        closePopover()
        for worker in sessions.values { worker.flushEdits() }
        for window in windows.values { window.orderOut(nil) }
        NSApp.hide(nil)
        queue.captureScreenshot(after: .milliseconds(120))
    }
    /// Kept as the command entry point, now switches the menu popover in place.
    func showTextWindow() {
        openPopover(composing: true)
    }
    private func configure(_ worker: ContentProcessViewModel) {
        worker.onSaveStarted = { [weak self, weak worker] in
            guard let self, let worker, let id = worker.record?.id else { return }
            savingWorkers[id] = worker
            windows["preview-\(id)"]?.close(); windows["error-\(id)"]?.close()
        }
        worker.onSaveFinished = { [weak self, weak worker] success in
            guard let self, let worker, let id = worker.record?.id else { return }
            savingWorkers[id] = nil
            if !success { present(worker, error: false) }
        }
    }
    private func present(_ worker: ContentProcessViewModel, error: Bool) {
        if queue.isCapturing { deferredPresentations.append((worker, error)); return }
        if let id = worker.record?.id {
            sessions[id] = worker
            windows["processing-\(id)"]?.close()
        }
        if error { showErrorWindow(worker) } else { showPreviewWindow(worker) }
    }
    func openRecord(_ requested: HistoryRecord) {
        guard requested.status != .queued, requested.status != .processing, requested.status != .saving, savingWorkers[requested.id] == nil else { return }
        closePopover()
        if let worker = sessions[requested.id] { present(worker, error: worker.record?.drafts.isEmpty == true && worker.failure != nil); return }
        let worker = ContentProcessViewModel(); configure(worker); worker.open(requested)
        present(worker, error: worker.record?.drafts.isEmpty == true && worker.failure != nil)
    }
    func showPreviewWindow() {
        if let latest = queue.latestWorker { present(latest, error: false) }
        else if viewModel.record != nil { present(viewModel, error: false) }
    }
    private func showPreviewWindow(_ worker: ContentProcessViewModel) {
        guard let id = worker.record?.id else { return }
        show("preview-\(id)", size: NSSize(width: 980, height: 650), minimum: NSSize(width: 740, height: 500), glass: true, activate: popover?.isShown != true) { PreviewWindow(viewModel: worker, retry: { [weak self, weak worker] in if let source = worker?.capturedSource { self?.queue.enqueue(source) } }) }
    }
    func showProcessingWindow() {
        closePopover()
        show("processing", size: NSSize(width: 650, height: 500), minimum: NSSize(width: 610, height: 440)) {
            ConcurrentProcessingView(queue: queue, background: { [weak self] in self?.windows["processing"]?.orderOut(nil) })
        }
    }
    private func showErrorWindow(_ worker: ContentProcessViewModel) {
        let id = worker.record?.id ?? worker.failure?.id ?? UUID()
        show("error-\(id)", size: NSSize(width: 680, height: 550), minimum: NSSize(width: 620, height: 480), activate: popover?.isShown != true) {
            ErrorStateView(viewModel: worker, settings: { [weak self] section in self?.showSettingsWindow(section: section) }, retry: { [weak self, weak worker] in
                guard let self, let worker else { return }
                if worker.failure?.kind == .permission { beginScreenshot() }
                else if let source = worker.capturedSource { windows["error-\(id)"]?.close(); queue.enqueue(source) }
                else { worker.notice = "这条记录没有保留截图原图，请重新截图。" }
            })
        }
    }
    func showSettingsWindow(section: SettingsSection = .models) {
        closePopover(); navigation.section = section
        show("settings", size: NSSize(width: 880, height: 650), minimum: NSSize(width: 760, height: 530)) {
            SettingsView(navigation: navigation, showHistory: { [weak self] in self?.showHistoryWindow() })
        }
    }
    func showHistoryWindow() {
        closePopover()
        show("history", size: NSSize(width: 880, height: 640), minimum: NSSize(width: 760, height: 500)) {
            HistoryView(store: .shared, queue: queue, didDelete: { [weak self] ids in self?.discardRecords(ids) }, input: { [weak self] in self?.showTextWindow() }, open: { [weak self] value in self?.openRecord(value) })
        }
    }
    private func discardRecords(_ ids: Set<UUID>) {
        queue.forgetHistory(ids)
        for id in ids {
            sessions[id]?.discardRecord()
            windows["preview-\(id)"]?.close(); windows["error-\(id)"]?.close()
            sessions[id] = nil
        }
    }
    func showWelcomeWindow() {
        show("welcome", size: NSSize(width: 900, height: 600), minimum: NSSize(width: 800, height: 530)) {
            WelcomeView(configure: { [weak self] in self?.windows["welcome"]?.orderOut(nil); self?.showSettingsWindow() }, tryInput: { [weak self] in self?.windows["welcome"]?.orderOut(nil); self?.showTextWindow() })
        }
    }
    func showAboutWindow() { closePopover(); show("about", size: NSSize(width: 540, height: 480), minimum: NSSize(width: 540, height: 480)) { AboutMiloView() } }
    func quit() { flushAndStop(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { flushAndStop() }
    private func flushAndStop() { removePopoverMonitors(); for worker in sessions.values { worker.flushEdits() }; queue.shutdown(); viewModel.flushEdits() }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let key = window.identifier?.rawValue else { return }
        if let value = key.split(separator: "-", maxSplits: 1).last, let id = UUID(uuidString: String(value)) {
            sessions[id]?.flushEdits()
            if !key.hasPrefix("processing-") { sessions[id] = nil }
            // Defer releasing the delegate's last window reference until the close callback returns.
            DispatchQueue.main.async { [weak self, weak window] in if self?.windows[key] === window, window?.isVisible == false { self?.windows[key] = nil } }
        }
    }
    private func show<Content: View>(_ key: String, size: NSSize, minimum: NSSize, glass: Bool = false, activate: Bool = true, @ViewBuilder content: () -> Content) {
        let window: NSWindow
        if let existing = windows[key], existing.isVisible { window = existing }
        else if let existing = windows[key] { window = existing }
        else {
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.identifier = NSUserInterfaceItemIdentifier(key); window.delegate = self
            window.title = miloWindowTitle; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.isOpaque = !glass; window.backgroundColor = glass ? .clear : NSColor(red: 0.957, green: 0.941, blue: 0.906, alpha: 1)
            window.isMovableByWindowBackground = true; window.isReleasedWhenClosed = false; window.minSize = minimum
            window.contentView = NSHostingView(rootView: content().preferredColorScheme(.light).tint(DesignSystem.Colors.primary))
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            window.setContentSize(NSSize(width: min(size.width, visible.width - 48), height: min(size.height, visible.height - 48))); window.center()
            if key.hasPrefix("preview-"), let previous = windows.values.first(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("preview-") == true }) {
                let old = previous.frame
                let x = min(max(visible.minX + 12, old.minX + 22), visible.maxX - window.frame.width - 12)
                let y = max(visible.minY + 12, old.maxY - window.frame.height - 22)
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            windows[key] = window
            if ["settings", "history"].contains(key) { window.setFrameAutosaveName("Milo.Compact2.\(key)") }
        }
        if activate { NSApp.unhideWithoutActivation(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else { window.orderFrontRegardless() }
    }
}
