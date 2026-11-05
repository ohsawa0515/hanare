import AppKit
import HanareCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var visibility = VisibilityController(
        backends: [AppVisibilityBackend()].compactMap { $0 } + [ControlCenterVisibilityBackend(), InputMenuVisibilityBackend()],
        store: HiddenItemsStore()
    )
    private lazy var coordinator = HidingCoordinator(visibility: visibility)
    private var statusBar: StatusBarController?
    private lazy var dragging = MenuBarDragging(settings: settings, coordinator: coordinator)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, actions: .init(
        restoreAll: { [weak self] in self?.coordinator.restoreAll() },
        setHidden: { [weak self] targets, hidden in await self?.setHidden(targets, hidden) }
    ))
    private lazy var aboutWindow = AboutWindowController()
    private var signalSources: [DispatchSourceSignal] = []
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProtectedFileAccess.activate()
        coordinator.restoreLeftovers()
        coordinator.targets = { [settings] in settings.hiddenTargets }
        coordinator.hoverTargets = { [settings] in settings.hoverTargets }
        coordinator.autoCollapseDelay = { [settings] in settings.autoCollapseDelay }
        coordinator.willExpand = { [weak self] in self?.dragging.keepHiddenOnLeft() }

        let statusBar = StatusBarController(settings: settings, coordinator: coordinator)
        statusBar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        statusBar.onOpenAbout = { [weak self] in self?.aboutWindow.show() }
        statusBar.onAccessGranted = { [weak self] in self?.applyLayout(attempt: 0) }
        statusBar.onClickWithoutChoice = { [weak self] in
            guard let self else { return }
            // Nothing chosen yet: take the icons left of the archer, or show where to choose.
            dragging.syncChoiceWithPositions()
            if settings.hiddenTargets.isEmpty { settingsWindow.show() } else { coordinator.collapse() }
        }
        self.statusBar = statusBar

        installTerminationSignals()
        observeSelection()
        dragging.start()

        // Icons restored above take a moment to settle back into the menu bar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.startHiding() }
    }

    /// Hides the icons to the left of the archer, or opens Settings when there are none.
    private func startHiding() {
        if !ProtectedFileAccess.hasAccess {
            statusBar?.requestAccess()
        }
        // Without the order file, positions can only be read with Accessibility.
        if !dragging.canMoveWithoutPointer, !MenuBarInspector.isTrusted(prompt: true) {
            waitForAccessibility()
        }
        applyLayout(attempt: 0)
    }

    /// Hides the icons to the left of the archer. The menu bar is not always fully readable right
    /// after launch, so an empty result is retried a few times before giving up.
    private func applyLayout(attempt: Int) {
        // Show All before the launch work finishes means the user wants the icons visible.
        guard coordinator.restoreAllCount == 0 else { return }
        dragging.syncChoiceWithPositions()
        if !settings.hiddenTargets.isEmpty {
            coordinator.collapse()
        } else if attempt < 4, dragging.canReadPositions || ProtectedFileAccess.hasAccess {
            // The order file can lag behind right after launch, before Hanare's own item is in it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.applyLayout(attempt: attempt + 1) }
        } else {
            settingsWindow.show()
        }
    }

    /// Applies a choice made in Settings and moves the icons to match: hidden icons to the left of
    /// the archer, shown icons to its right.
    private func setHidden(_ targets: [HideTarget], _ hidden: Bool) async {
        // Show All while an icon is being moved wins over hiding it afterwards.
        let restoreAllCount = coordinator.restoreAllCount
        // While icons are being revealed one by one, a deselected icon may still be queued; bring
        // it back now so it is placed on the right like the others.
        if !hidden { coordinator.restore(targets) }
        if dragging.canMoveWithoutPointer {
            await dragging.place(targets, hidden: hidden)
        } else if hidden {
            await dragging.place(targets, hidden: true)
        } else {
            settings.setHidden(false, for: targets)
            coordinator.selectionChanged()  // a Command-drag needs the icons back on screen first
            try? await Task.sleep(for: .milliseconds(600))
            await dragging.place(targets, hidden: false)
            return
        }
        if hidden, coordinator.restoreAllCount != restoreAllCount { return }
        settings.setHidden(hidden, for: targets)
    }

    /// Reads the menu bar layout as soon as the user allows Accessibility.
    private func waitForAccessibility() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, MenuBarInspector.isTrusted(prompt: false) else { return }
                self.accessibilityTimer?.invalidate()
                guard self.coordinator.restoreAllCount == 0 else { return }
                self.dragging.syncChoiceWithPositions()
                if !self.settings.hiddenTargets.isEmpty { self.coordinator.collapse() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.restoreAll()
    }

    /// Applies changes made in Settings right away.
    private func observeSelection() {
        withObservationTracking {
            _ = settings.hiddenTargets
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.coordinator.selectionChanged()
                self?.observeSelection()
            }
        }
    }

    /// Restores hidden icons before exiting on Ctrl+C or `kill`.
    private func installTerminationSignals() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            source.resume()
            signalSources.append(source)
        }
    }
}
