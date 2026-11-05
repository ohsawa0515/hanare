import AppKit
import HanareCore

/// Owns Hanare's menu bar item: the archer that hides and reveals the chosen icons.
@MainActor
final class StatusBarController {
    private enum Const {
        /// How long the release pose is shown before the follow-through.
        static let releaseDuration: TimeInterval = 0.35
    }

    static let autosaveName = "Hanare.toggle"

    var onOpenSettings: (() -> Void)?
    /// Called when the archer is clicked while no icon is chosen.
    var onClickWithoutChoice: (() -> Void)?
    /// Called when the user has just allowed access to the menu bar files.
    var onAccessGranted: (() -> Void)?

    private let settings: AppSettings
    private let coordinator: HidingCoordinator
    private let item: NSStatusItem

    private var isHovering = false
    private var isReleasing = false
    private var didRequestAccess = false
    private var releaseTimer: Timer?

    init(settings: AppSettings, coordinator: HidingCoordinator) {
        self.settings = settings
        self.coordinator = coordinator

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.autosaveName
        item.button?.toolTip = "Hanare"

        if let button = item.button {
            button.target = self
            button.action = #selector(itemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let hoverView = HoverTrackingView(frame: button.bounds)
            hoverView.autoresizingMask = [.width, .height]
            hoverView.onHoverChanged = { [weak self] hovering in
                self?.isHovering = hovering
                self?.updateAppearance()
            }
            button.addSubview(hoverView)
        }

        coordinator.onStateChange = { [weak self] state in self?.stateDidChange(state) }
        coordinator.onSettingsAccessDenied = { [weak self] in self?.requestAccess() }
        observeSettings()
        updateAppearance()
    }

    // MARK: - Interaction

    @objc private func itemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else if settings.hiddenTargets.isEmpty, coordinator.currentlyHidden.isEmpty {
            // Icons still hidden after a failed restore are revealed by a normal click instead.
            onClickWithoutChoice?()
        } else {
            coordinator.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.showAllIcons, action: #selector(showAllSelected), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.settings, action: #selector(settingsSelected), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func showAllSelected() { coordinator.restoreAll() }
    @objc private func settingsSelected() { onOpenSettings?() }

    /// Asks once per launch for the menu bar files macOS protects.
    func requestAccess() {
        guard !didRequestAccess else { return }
        didRequestAccess = true
        if ProtectedFileAccess.request() { onAccessGranted?() }
    }

    // MARK: - Appearance

    private func stateDidChange(_ state: HidingCoordinator.State) {
        releaseTimer?.invalidate()
        isReleasing = state == .expanded
        if isReleasing {
            releaseTimer = Timer.scheduledTimer(withTimeInterval: Const.releaseDuration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isReleasing = false
                    self?.updateAppearance()
                }
            }
        }
        updateAppearance()
    }

    private func updateAppearance() {
        item.button?.image = CharacterImages.image(style: settings.character, pose: currentPose)
    }

    private var currentPose: Pose {
        switch coordinator.state {
        case .expanded: isReleasing ? .hanare : .zanshin
        case .idle, .collapsed: isHovering ? .kai : .yugamae
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.character
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateAppearance()
                self?.observeSettings()
            }
        }
    }
}

/// Reports the mouse entering and leaving the button without intercepting clicks.
private final class HoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
