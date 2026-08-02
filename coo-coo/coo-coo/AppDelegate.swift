import AppKit
import SwiftUI
import Combine
import UserNotifications

extension Notification.Name {
    static let coocooShowPreferences = Notification.Name("coocoo.showPreferences")
    static let coocooToggleWidget = Notification.Name("coocoo.toggleWidget")
}

// Keeps a panel frame fully within the visibleFrame of whichever screen it's on
// (falls back to the main screen if the origin isn't within any screen's bounds,
// e.g. after an external monitor is disconnected). Used for the floating widget's
// resize, restore, and drag paths so it can never end up off-screen.
fileprivate func clampToScreen(_ frame: NSRect) -> NSRect {
    let screen = NSScreen.screens.first(where: { $0.frame.contains(frame.origin) }) ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return frame }
    var f = frame
    f.origin.x = min(max(f.origin.x, visible.minX), max(visible.minX, visible.maxX - f.width))
    f.origin.y = min(max(f.origin.y, visible.minY), max(visible.minY, visible.maxY - f.height))
    return f
}

// NSHostingView subclass for the floating widget.
// • acceptsFirstMouse — clicks reach SwiftUI without the app needing to be frontmost.
// • mouseDragged      — moves the panel at AppKit level for smooth, zero-lag dragging.
//   Uses absolute NSEvent.mouseLocation so there's no delta-sign ambiguity.
private class ClickableHostingView<Content: View>: NSHostingView<Content> {
    private var dragStartWindowOrigin: NSPoint?
    private var dragStartMouseLocation: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStartWindowOrigin = window?.frame.origin
        dragStartMouseLocation = NSEvent.mouseLocation
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let startOrigin = dragStartWindowOrigin,
              let startMouse  = dragStartMouseLocation else { return }
        let cur = NSEvent.mouseLocation
        let proposed = NSRect(
            origin: NSPoint(
                x: startOrigin.x + (cur.x - startMouse.x),
                y: startOrigin.y + (cur.y - startMouse.y)
            ),
            size: window.frame.size
        )
        window.setFrameOrigin(clampToScreen(proposed).origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartWindowOrigin = nil
        dragStartMouseLocation = nil
        super.mouseUp(with: event)
    }
}

// Tracks one active Claude Code session.
private class SessionHandle {
    let store: CompanionStateStore
    let statusItem: NSStatusItem
    let popover: NSPopover
    let accentColor: NSColor
    var cancellables = Set<AnyCancellable>()
    var removalTimer: Timer?
    var inactivityTimer: Timer?
    var reapTimer: Timer?

    init(store: CompanionStateStore, statusItem: NSStatusItem, popover: NSPopover, accentColor: NSColor) {
        self.store = store
        self.statusItem = statusItem
        self.popover = popover
        self.accentColor = accentColor
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var sessions: [String: SessionHandle] = [:]
    private var sessionColorIndex = 0
    private var hookListener: HookListener!
    private var preferencesWindow: NSWindow?

    // If a `claude` process is killed/crashes without ever firing the Stop
    // hook (Ctrl-C hard-kill, terminal window closed, crash), its session
    // would otherwise leak in the menu bar forever — resetInactivityTimer
    // only demotes thinking/waiting to idle, it never removes anything.
    // This is the actual reap: no hook event of any kind for this long means
    // the session is almost certainly dead, not just a user thinking for a
    // while. Long enough that a real coffee-break pause never gets caught by
    // it — if the session is in fact still alive, the very next hook event
    // just recreates its icon fresh, so a false reap is cheap and harmless.
    private let sessionReapInterval: TimeInterval = 30 * 60

    private static let sessionColors: [NSColor] = [
        NSColor(red: 0.00, green: 0.74, blue: 0.83, alpha: 1), // teal
        NSColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1), // coral
        NSColor(red: 1.00, green: 0.76, blue: 0.03, alpha: 1), // amber
        NSColor(red: 0.61, green: 0.35, blue: 0.71, alpha: 1), // lavender
        NSColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 1), // mint
        NSColor(red: 1.00, green: 0.60, blue: 0.00, alpha: 1), // orange
    ]

    // Background idle Gerald when no sessions are active.
    private var bgStatusItem: NSStatusItem?
    private var bgPopover: NSPopover?
    private let bgStore = CompanionStateStore()

    // Floating overlay widget.
    private let floatingStore = FloatingStore()
    private var floatingPanel: NSPanel?
    private let alertPerformance = AlertPerformanceController()
    private static let widgetExpandedSize = NSSize(width: 164, height: 300)
    private static let widgetMiniSize = NSSize(width: 72, height: 72)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestNotificationPermission()
        showBackgroundItem()
        startHookListener()
        installHooksIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(openPreferencesFromNotification(_:)), name: .coocooShowPreferences, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWidgetToggle(_:)), name: .coocooToggleWidget, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAllIcons), name: .coocooCharacterChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWidgetResize), name: .coocooWidgetResized, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenTerminal(_:)), name: .coocooOpenTerminal, object: nil)
        let showWidget = UserDefaults.standard.object(forKey: "showFloatingWidget") as? Bool ?? true
        if showWidget { setupFloatingWidget() }
    }

    private func installHooksIfNeeded() {
        guard HookInstaller.currentStatus() != .installed else { return }
        DispatchQueue.global(qos: .utility).async {
            HookInstaller.install()
            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: "hooksJustInstalled")
            }
        }
    }

    // MARK: - Background item (zero-session placeholder)

    private func showBackgroundItem() {
        guard bgStatusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.action = #selector(toggleBgPopover)
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        Task { @MainActor in self.updateIcon(item, state: .idle, accentColor: nil) }
        bgPopover = makePopover(store: bgStore)
        bgStatusItem = item
    }

    private func hideBackgroundItem() {
        guard let item = bgStatusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        bgStatusItem = nil
        bgPopover = nil
    }

    @objc private func toggleBgPopover() {
        guard let button = bgStatusItem?.button, let popover = bgPopover else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(buildBgContextMenu(), for: button)
        } else {
            togglePopover(popover, relativeTo: button)
        }
    }

    // MARK: - Session management

    private func handleEvent(state: CompanionState, message: String, sessionId: String, cwd: String, detail: String = "") {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let id = sessionId.isEmpty ? "default" : sessionId

            if let handle = self.sessions[id] {
                handle.removalTimer?.invalidate()
                handle.removalTimer = nil
                if !cwd.isEmpty { handle.store.cwd = cwd }
                handle.store.transition(to: state, message: message, detail: detail)
                if state == .done {
                    handle.inactivityTimer?.invalidate()
                    handle.reapTimer?.invalidate()
                    self.scheduleDoneRemoval(id: id, handle: handle)
                } else {
                    self.resetInactivityTimer(id: id, handle: handle)
                }
            } else {
                self.hideBackgroundItem()

                let color = Self.sessionColors[self.sessionColorIndex % Self.sessionColors.count]
                self.sessionColorIndex += 1

                let store = CompanionStateStore()
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItem.button?.action = #selector(self.sessionButtonTapped(_:))
                statusItem.button?.target = self
                statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                let popover = self.makePopover(store: store)
                let handle = SessionHandle(store: store, statusItem: statusItem, popover: popover, accentColor: color)

                store.$state
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] newState in
                        Task { @MainActor [weak self] in
                            self?.updateIcon(statusItem, state: newState, accentColor: color)
                        }
                        self?.updateFloatingState()
                    }
                    .store(in: &handle.cancellables)

                store.cwd = cwd
                store.onDismiss = { [weak self] in self?.removeSession(id: id) }
                self.sessions[id] = handle
                store.transition(to: state, message: message, detail: detail)
                Task { @MainActor in self.updateIcon(statusItem, state: state, accentColor: color) }

                if state == .done {
                    self.scheduleDoneRemoval(id: id, handle: handle)
                } else {
                    self.resetInactivityTimer(id: id, handle: handle)
                }
            }

            self.updateFloatingState()
        }
    }

    private func resetInactivityTimer(id: String, handle: SessionHandle) {
        handle.inactivityTimer?.invalidate()
        handle.inactivityTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            guard let self, let handle = self.sessions[id] else { return }
            if handle.store.state == .thinking || handle.store.state == .waiting {
                handle.store.transition(to: .idle)
            }
        }
        resetReapTimer(id: id, handle: handle)
    }

    private func resetReapTimer(id: String, handle: SessionHandle) {
        handle.reapTimer?.invalidate()
        handle.reapTimer = Timer.scheduledTimer(withTimeInterval: sessionReapInterval, repeats: false) { [weak self] _ in
            self?.removeSession(id: id)
        }
    }

    private func scheduleDoneRemoval(id: String, handle: SessionHandle) {
        let timeout = UserDefaults.standard.object(forKey: "doneTimeout") as? Double ?? 30.0
        guard timeout > 0 else { return }
        handle.removalTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.removeSession(id: id)
        }
    }

    private func removeSession(id: String) {
        guard let handle = sessions[id] else { return }
        handle.removalTimer?.invalidate()
        handle.inactivityTimer?.invalidate()
        handle.reapTimer?.invalidate()
        handle.cancellables.removeAll()
        if handle.popover.isShown { handle.popover.performClose(nil) }
        stopIconAnimation(for: handle.statusItem)
        NSStatusBar.system.removeStatusItem(handle.statusItem)
        sessions.removeValue(forKey: id)
        if sessions.isEmpty { showBackgroundItem() }
        updateFloatingState()
    }

    @objc private func sessionButtonTapped(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton,
              let entry = sessions.first(where: { $0.value.statusItem.button === button }) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(buildSessionContextMenu(id: entry.key, handle: entry.value), for: button)
        } else {
            togglePopover(entry.value.popover, relativeTo: button)
        }
    }

    // MARK: - Popover helpers

    private func togglePopover(_ popover: NSPopover, relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Context menus

    private func showContextMenu(_ menu: NSMenu, for button: NSStatusBarButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: -1, y: button.bounds.height + 3), in: button)
    }

    private func buildBgContextMenu() -> NSMenu {
        let menu = NSMenu()
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesMenu), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit CooCoo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func buildSessionContextMenu(id: String, handle: SessionHandle) -> NSMenu {
        let menu = NSMenu()
        let dismiss = NSMenuItem(title: "Dismiss session", action: #selector(menuDismissSession(_:)), keyEquivalent: "")
        dismiss.target = self
        dismiss.representedObject = id
        menu.addItem(dismiss)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesMenu), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit CooCoo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func menuDismissSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        removeSession(id: id)
    }

    @objc private func openPreferencesMenu() {
        openPreferences()
    }

    private func makePopover(store: CompanionStateStore) -> NSPopover {
        let p = NSPopover()
        p.contentSize = NSSize(width: 220, height: 190)
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: PopoverView().environmentObject(store))
        return p
    }

    // MARK: - Icon

    // Per-item animation timers keyed by item pointer address.
    private var iconTimers: [ObjectIdentifier: Timer] = [:]

    @MainActor
    private func updateIcon(_ item: NSStatusItem, state: CompanionState, accentColor: NSColor?) {
        renderIconImage(for: item, state: state, accentColor: accentColor)
        updateIconAnimation(for: item, state: state, accentColor: accentColor)
    }

    @MainActor
    private func renderIconImage(for item: NSStatusItem, state: CompanionState, accentColor: NSColor?) {
        let characterId = UserDefaults.standard.string(forKey: "selectedCharacter") ?? "pigeon"
        let character = CharacterID(rawValue: characterId) ?? .pigeon
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        // Canvas reads Date() inside the closure so each render produces the
        // correct animation frame when called from a timer.
        let iconView = Canvas { ctx, size in
            let t = Date().timeIntervalSinceReferenceDate
            CharacterMenuBarRenderer.render(ctx: ctx, size: size, character: character, state: state, t: t)
        }.frame(width: 22, height: 22)
        let renderer = ImageRenderer(content: iconView)
        renderer.scale = scale
        guard let charImage = renderer.nsImage else { return }

        let finalImage: NSImage
        if let color = accentColor {
            finalImage = NSImage(size: charImage.size, flipped: false) { rect in
                charImage.draw(in: rect)
                NSColor.white.withAlphaComponent(0.9).setFill()
                NSBezierPath(ovalIn: CGRect(x: rect.maxX - 7.5, y: rect.minY + 0.5, width: 7, height: 7)).fill()
                color.setFill()
                NSBezierPath(ovalIn: CGRect(x: rect.maxX - 6.5, y: rect.minY + 1.5, width: 5, height: 5)).fill()
                return true
            }
        } else {
            finalImage = charImage
        }

        finalImage.isTemplate = false
        item.button?.image = finalImage
        item.button?.title = ""
    }

    private func updateIconAnimation(for item: NSStatusItem, state: CompanionState, accentColor: NSColor?) {
        let key = ObjectIdentifier(item)
        iconTimers[key]?.invalidate()
        iconTimers.removeValue(forKey: key)

        guard state == .waiting || state == .thinking || state == .done else { return }
        // Animate at 12fps while state is active.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self, weak item] _ in
            guard let self, let item else { return }
            Task { @MainActor in
                self.renderIconImage(for: item, state: state, accentColor: accentColor)
            }
        }
        iconTimers[key] = timer
    }

    private func stopIconAnimation(for item: NSStatusItem) {
        let key = ObjectIdentifier(item)
        iconTimers[key]?.invalidate()
        iconTimers.removeValue(forKey: key)
    }

    // MARK: - Floating widget

    private func setupFloatingWidget() {
        guard floatingPanel == nil else { return }

        let isMinimized = UserDefaults.standard.bool(forKey: "widgetMinimized")
        let initialSize = isMinimized ? Self.widgetMiniSize : Self.widgetExpandedSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let hostingView = ClickableHostingView(rootView: FloatingWidgetView(store: floatingStore))
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        panel.contentView = hostingView

        restoreOrDefaultPosition(panel)
        panel.orderFront(nil)
        floatingPanel = panel

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveFloatingWidgetPosition),
            name: NSWindow.didMoveNotification,
            object: panel
        )
    }

    private func teardownFloatingWidget() {
        guard let panel = floatingPanel else { return }
        saveFloatingWidgetPosition()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: panel)
        panel.orderOut(nil)
        floatingPanel = nil
    }

    private func restoreOrDefaultPosition(_ panel: NSPanel) {
        if let saved = UserDefaults.standard.dictionary(forKey: "floatingWidgetOrigin"),
           let x = saved["x"] as? Double,
           let y = saved["y"] as? Double {
            let saved = NSRect(origin: NSPoint(x: x, y: y), size: panel.frame.size)
            panel.setFrameOrigin(clampToScreen(saved).origin)
        } else {
            if let screen = NSScreen.main {
                let margin: CGFloat = 24
                let x = screen.visibleFrame.maxX - panel.frame.width - margin
                let y = screen.visibleFrame.minY + margin
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                panel.center()
            }
        }
    }

    @objc private func saveFloatingWidgetPosition() {
        guard let panel = floatingPanel else { return }
        let origin = panel.frame.origin
        UserDefaults.standard.set(["x": Double(origin.x), "y": Double(origin.y)], forKey: "floatingWidgetOrigin")
    }

    @objc private func handleWidgetResize() {
        guard let panel = floatingPanel else { return }
        let isMinimized = UserDefaults.standard.bool(forKey: "widgetMinimized")
        let newSize = isMinimized ? Self.widgetMiniSize : Self.widgetExpandedSize
        let oldFrame = panel.frame
        panel.setContentSize(newSize)
        // Keep the top-left corner of the panel fixed so the widget doesn't jump around,
        // then clamp — growing from a corner position can otherwise push the new,
        // larger frame past the screen's edge.
        let newOriginY = oldFrame.maxY - newSize.height
        let proposed = NSRect(origin: NSPoint(x: oldFrame.minX, y: newOriginY), size: newSize)
        panel.setFrameOrigin(clampToScreen(proposed).origin)
    }

    @objc private func handleWidgetToggle(_ notification: Notification) {
        guard let show = notification.object as? Bool else { return }
        if show {
            setupFloatingWidget()
        } else {
            teardownFloatingWidget()
        }
    }

    // Tapping the expanded widget's character jumps back to the terminal the
    // user was already running Claude Code in, rather than opening a new,
    // unrelated window — TerminalInjector already knows how to find and
    // activate whichever supported terminal app (iTerm2/Terminal/Warp/Ghostty)
    // is running.
    @objc private func handleOpenTerminal(_ notification: Notification) {
        TerminalInjector.activate()
    }

    // The widget is a single card — it can only ever show one session's state
    // at a time — so with multiple sessions active simultaneously, whichever
    // one isn't picked here would otherwise go completely invisible on the
    // widget (its menu bar icon is still correct either way). otherCount
    // surfaces that as a small "+N" badge instead of silently dropping it.
    private func updateFloatingState() {
        guard !sessions.isEmpty else {
            floatingStore.state = .idle
            floatingStore.message = ""
            floatingStore.otherCount = 0
            floatingStore.projectName = ""
            floatingStore.detail = ""
            updateAlertPerformance(isWaiting: false)
            return
        }
        let priority: [CompanionState] = [.waiting, .thinking, .done, .sleepy, .idle]
        let all = sessions.values
        let topState = priority.first { s in all.contains { $0.store.state == s } } ?? .idle
        // Ties (multiple sessions sharing topState) are broken by session id,
        // not by iterating `sessions.values` directly — a Dictionary's value
        // order isn't guaranteed, so without a stable tie-break the message
        // shown could flicker between sessions across otherwise-unrelated
        // updates.
        let topId = sessions.keys.filter { sessions[$0]?.store.state == topState }.sorted().first
        let topSession = topId.flatMap { sessions[$0] }
        floatingStore.state = topState
        floatingStore.message = topSession?.store.message ?? ""
        floatingStore.otherCount = max(0, sessions.count - 1)
        // Populated unconditionally — FloatingWidgetView decides whether to
        // show these based on the "Extended mode" preference, not this call site.
        floatingStore.projectName = topSession?.store.displayCwd ?? ""
        floatingStore.detail = topSession?.store.detail ?? ""
        updateAlertPerformance(isWaiting: topState == .waiting)
    }

    // MARK: - Alert Style (Walk / Hang)
    //
    // A separate, card-less character panel (not the pinned widget) performs a
    // short, finite burst of motion — a few walk-hops or hang-drops — then
    // fades out on its own. It's edge-triggered off entering .waiting (not
    // re-fired on every subsequent event while still waiting), so it doesn't
    // loop or linger and compete with the pinned widget for attention.

    private var alertPerformedForCurrentWait = false

    private func updateAlertPerformance(isWaiting: Bool) {
        if isWaiting {
            guard !alertPerformedForCurrentWait else { return }
            alertPerformedForCurrentWait = true
            let charId = UserDefaults.standard.string(forKey: "selectedCharacter") ?? "pigeon"
            let character = CharacterID(rawValue: charId) ?? .pigeon
            let style = UserDefaults.standard.string(forKey: "alertStyle") ?? "shake"
            alertPerformance.perform(style: style, character: character)
        } else if alertPerformedForCurrentWait {
            alertPerformedForCurrentWait = false
            alertPerformance.cancel()
        }
    }

    @objc private func refreshAllIcons() {
        Task { @MainActor in
            for handle in self.sessions.values {
                self.updateIcon(handle.statusItem, state: handle.store.state, accentColor: handle.accentColor)
            }
            if let bgItem = self.bgStatusItem {
                self.updateIcon(bgItem, state: self.bgStore.state, accentColor: nil)
            }
        }
    }

    // MARK: - Preferences window

    @objc private func openPreferencesFromNotification(_ notification: Notification) {
        openPreferences()
    }

    private func openPreferences() {
        if let window = preferencesWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CooCoo Preferences"
        window.isReleasedWhenClosed = false
        let hostingController = NSHostingController(rootView: PreferencesView())
        window.contentViewController = hostingController
        window.setContentSize(hostingController.view.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow = window
    }

    // MARK: - Setup

    private func startHookListener() {
        hookListener = HookListener()
        hookListener.onEvent = { [weak self] state, message, sessionId, cwd, detail in
            self?.handleEvent(state: state, message: message, sessionId: sessionId, cwd: cwd, detail: detail)
        }
        hookListener.start()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
