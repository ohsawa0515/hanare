import Foundation
import os

/// Drives hiding and revealing: applies the user's selection, keeps the state, and runs the timers.
@MainActor
public final class HidingCoordinator {
    public enum State: Equatable, Sendable {
        /// Nothing is hidden.
        case idle
        /// The selected icons are hidden.
        case collapsed
        /// Hidden icons are shown again.
        case expanded
    }

    public enum Timing {
        /// Interval between icons when revealing, so they appear one after another like a flying arrow.
        public static let revealInterval: TimeInterval = 0.06
    }

    public private(set) var state = State.idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public var onStateChange: ((State) -> Void)?
    /// Called when icons cannot be hidden because macOS denies access to their settings.
    public var onSettingsAccessDenied: (() -> Void)?
    /// Called right before hidden icons are revealed, while they are still off the menu bar.
    public var willExpand: (() -> Void)?

    /// The icons the user chose to hide, in the order they are revealed.
    public var targets: () -> [HideTarget] = { [] }
    /// Seconds before revealed icons are hidden again. `0` disables it.
    public var autoCollapseDelay: () -> TimeInterval = { 0 }

    private let visibility: VisibilityController
    private let logger = Logger(subsystem: "io.github.ohsawa0515.Hanare", category: "coordinator")
    private var revealTimer: Timer?
    private var autoCollapseTimer: Timer?

    public init(visibility: VisibilityController) {
        self.visibility = visibility
    }

    /// Restores anything left hidden by a previous run that ended unexpectedly.
    /// Icons Hanare is hiding right now.
    public var currentlyHidden: Set<HideTarget> { Set(visibility.hiddenItems.map(\.target)) }

    public func isVisible(_ target: HideTarget) -> Bool { visibility.isVisible(target) }

    public func restoreLeftovers() {
        guard !visibility.hiddenItems.isEmpty else { return }
        logger.notice("Restoring \(self.visibility.hiddenItems.count) item(s) left hidden")
        visibility.restoreAll()
    }

    public func toggle() {
        switch state {
        case .idle, .expanded: collapse()
        case .collapsed: expand()
        }
    }

    /// Applies a changed selection right away unless the icons are currently revealed.
    public func selectionChanged() {
        if state != .expanded { collapse() }
    }

    /// Hides the selected icons and shows the ones that are no longer selected.
    public func collapse() {
        cancelTimers()
        let wanted = targets()
        for item in visibility.hiddenItems where !wanted.contains(item.target) {
            visibility.restore(item.target)
        }
        let denied = visibility.inaccessible(wanted)
        visibility.hide(wanted)
        state = visibility.hiddenItems.isEmpty ? .idle : .collapsed
        if !denied.isEmpty {
            logger.error("Access to the settings of \(denied.count) item(s) was denied")
            onSettingsAccessDenied?()
        }
    }

    /// Reveals hidden icons one by one, starting with the first selected.
    public func expand() {
        cancelTimers()
        willExpand?()
        var queue = visibility.hiddenItems.map(\.target)
        state = .expanded
        revealTimer = Timer.scheduledTimer(withTimeInterval: Timing.revealInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, !queue.isEmpty else {
                    self?.revealTimer?.invalidate()
                    return
                }
                self.visibility.restore(queue.removeFirst())
            }
        }
        scheduleAutoCollapse()
    }

    /// Shows every hidden icon and stops hiding until the user collapses again.
    public func restoreAll() {
        cancelTimers()
        visibility.restoreAll()
        state = .idle
    }

    private func scheduleAutoCollapse() {
        let delay = autoCollapseDelay()
        guard delay > 0 else { return }
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .expanded else { return }
                self.collapse()
            }
        }
    }

    private func cancelTimers() {
        revealTimer?.invalidate()
        autoCollapseTimer?.invalidate()
    }
}
