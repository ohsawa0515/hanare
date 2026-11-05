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
        /// Only the icons chosen for hover are shown, while the pointer is over the archer (会).
        case peeking
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
    /// The hidden icons that appear on hover.
    public var hoverTargets: () -> [HideTarget] = { [] }
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
        case .collapsed, .peeking: expand()
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
        visibility.restore(visibility.hiddenItems.map(\.target).filter { !wanted.contains($0) })
        let denied = visibility.inaccessible(wanted)
        visibility.hide(wanted)
        state = visibility.hiddenItems.isEmpty ? .idle : .collapsed
        if !denied.isEmpty {
            logger.error("Access to the settings of \(denied.count) item(s) was denied")
            onSettingsAccessDenied?()
        }
    }

    /// Reveals only the icons chosen for hover. Does nothing unless the icons are hidden.
    public func peek() {
        guard state == .collapsed else { return }
        let wanted = Set(hoverTargets())
        let queue = revealOrder().filter(wanted.contains)
        guard !queue.isEmpty else { return }
        cancelTimers()
        willExpand?()
        state = .peeking
        reveal(queue) {}
    }

    /// Hides the icons shown by ``peek()`` again.
    public func endPeek() {
        if state == .peeking { collapse() }
    }

    /// Reveals hidden icons one by one, starting with the first selected.
    public func expand() {
        cancelTimers()
        willExpand?()
        state = .expanded
        reveal(revealOrder()) { [weak self] in
            guard let self else { return }
            if self.visibility.hiddenItems.isEmpty {
                // The hide-again delay counts from when the last icon is back.
                self.scheduleAutoCollapse()
            } else {
                // Some restores failed: those icons are still hidden, so the next click
                // should try to reveal them again.
                self.state = .collapsed
            }
        }
    }

    /// The hidden icons in the order the user chose them. Restoring and hiding an icon again moves it
    /// to the end of the journal, so the order is rebuilt from the selection. Icons no longer
    /// selected but still hidden come last, so a failed restore can be retried.
    private func revealOrder() -> [HideTarget] {
        let chosen = targets()
        let hidden = visibility.hiddenItems.map(\.target)
        return chosen.filter(hidden.contains) + hidden.filter { !chosen.contains($0) }
    }

    private func reveal(_ targets: [HideTarget], completion: @escaping @MainActor () -> Void) {
        var queue = targets
        revealTimer = Timer.scheduledTimer(withTimeInterval: Timing.revealInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !queue.isEmpty else {
                    self.revealTimer?.invalidate()
                    completion()
                    return
                }
                self.visibility.restore(queue.removeFirst())
            }
        }
    }

    /// Shows the given icons right away if Hanare hid them.
    public func restore(_ targets: [HideTarget]) {
        visibility.restore(targets)
        if visibility.hiddenItems.isEmpty, state == .collapsed { state = .idle }
    }

    /// Shows every hidden icon and stops hiding until the user collapses again.
    public func restoreAll() {
        cancelTimers()
        restoreAllCount += 1
        visibility.restoreAll()
        // Items a backend failed to restore are still hidden, so the next click retries the reveal.
        state = visibility.hiddenItems.isEmpty ? .idle : .collapsed
    }

    /// Increases on every Show All, so a slow change started earlier can tell it was overtaken.
    public private(set) var restoreAllCount = 0

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
