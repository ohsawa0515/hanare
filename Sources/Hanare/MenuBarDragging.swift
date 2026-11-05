import AppKit
import HanareCore

/// Everything that depends on where icons sit in the menu bar.
///
/// Positions come from the menu bar order file when the user has allowed it, which also lets
/// icons be moved without the pointer. Otherwise they are read through Accessibility and icons
/// are moved with a synthetic Command-drag. Noticing the user's own Command-drags always needs
/// Accessibility.
@MainActor
final class MenuBarDragging {
    private enum Const {
        /// Time for the menu bar to settle after a drop before positions are read.
        static let settleDelay: Duration = .milliseconds(800)
        static let moveSettleDelay: Duration = .milliseconds(500)
    }

    private let settings: AppSettings
    private let coordinator: HidingCoordinator
    private let inspector = MenuBarInspector()
    private let positionStore = MenuBarPositionStore(ownAutosaveName: StatusBarController.autosaveName)
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private var monitor: Any?
    private var isMoving = false
    private var didPrompt = false
    /// The icon being dragged.
    private var dragged: HideTarget?

    init(settings: AppSettings, coordinator: HidingCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
    }

    // MARK: - Dragging by the user

    /// Watches Command-drags in the menu bar: icons dropped to the left of the archer are hidden,
    /// icons dropped to its right are shown.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            let isDown = event.type == .leftMouseDown
            let command = event.modifierFlags.contains(.command)
            Task { @MainActor in
                if isDown { self?.mouseDown(command: command) } else { await self?.mouseUp() }
            }
        }
    }

    private func mouseDown(command: Bool) {
        dragged = nil
        guard command, !isMoving, Self.isInMenuBar(NSEvent.mouseLocation) else { return }
        guard MenuBarInspector.isTrusted(prompt: false) else {
            if !didPrompt {
                didPrompt = true
                _ = MenuBarInspector.isTrusted(prompt: true)
            }
            return
        }
        // Dragging the archer itself is the user rearranging the menu bar, not choosing icons.
        dragged = MenuBarLayout.target(at: Self.axPoint(NSEvent.mouseLocation), in: inspector.snapshots(), ownPID: ownPID)
    }

    private func mouseUp() async {
        guard let target = dragged else { return }
        dragged = nil
        let dropPoint = Self.axPoint(NSEvent.mouseLocation)
        try? await Task.sleep(for: Const.settleDelay)
        let items = inspector.snapshots()
        guard let toggle = items.first(where: { $0.pid == ownPID })?.frame,
              let side = MenuBarLayout.side(of: target, droppedNear: dropPoint, in: items, relativeTo: toggle, ownPID: ownPID)
        else { return }
        settings.setHidden(side == .left, for: [target])
        keepHiddenOnLeft()
    }

    /// MenuBarAgent rewrites the positions of the icons on screen when the user drags one, but not
    /// those of hidden icons, which can then end up on the archer's right. Puts them back on its left.
    func keepHiddenOnLeft() {
        guard let positionStore, var positions = positionStore.read() else { return }
        let before = positions
        positions.place(Set(settings.hiddenTargets), on: .left)
        if positions != before { positionStore.write(positions) }
    }

    // MARK: - At launch

    /// Makes the choice match the menu bar: icons to the left of the archer are hidden, icons to
    /// its right are not. Icons that are not on screen keep their setting.
    func syncChoiceWithPositions() {
        if var positions = positionStore?.read() {
            if positions.isCrowded {
                positions.spreadOut()
                positionStore?.write(positions)
            }
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let isPresent: (HideTarget) -> Bool = { target in
                if case .app(let bundleID) = target { running.contains(bundleID) } else { true }
            }
            let sides = positions.sides(where: isPresent)
            let hide = positions.targetsOnLeft(where: isPresent).filter { sides[$0] == [.left] && coordinator.isVisible($0) }
            apply(hide: hide, show: sides.filter { $0.value == [.right] }.map(\.key))
            return
        }
        guard MenuBarInspector.isTrusted(prompt: false) else { return }
        let items = inspector.snapshots()
        guard let toggle = items.first(where: { $0.pid == ownPID })?.frame else { return }
        let sides = MenuBarLayout.sides(of: items, relativeTo: toggle, ownPID: ownPID)
        // Ordered from the icon nearest to the archer, which is the order they are revealed in.
        var hide: [HideTarget] = []
        for item in items.sorted(by: { $0.frame.minX > $1.frame.minX }) {
            guard let target = MenuBarLayout.target(for: item), sides[target] == [.left],
                  !hide.contains(target), coordinator.isVisible(target) else { continue }
            hide.append(target)
        }
        apply(hide: hide, show: sides.filter { $0.value == [.right] }.map(\.key))
    }

    /// Whether icon positions can be read at all.
    var canReadPositions: Bool {
        positionStore?.read() != nil || MenuBarInspector.isTrusted(prompt: false)
    }

    private func apply(hide: [HideTarget], show: [HideTarget]) {
        settings.setHidden(false, for: show)
        settings.setHidden(true, for: hide)
    }

    // MARK: - Moving icons for the user

    /// Whether icons can be moved by rewriting the menu bar order, without the pointer.
    var canMoveWithoutPointer: Bool { positionStore?.read() != nil }

    /// Keeps icons where their setting says: hidden icons to the left of the archer, the others to
    /// its right. Without the order file this falls back to a Command-drag, which needs
    /// Accessibility and only reaches icons that are on screen.
    func place(_ targets: [HideTarget], hidden: Bool) async {
        if let positionStore, var positions = positionStore.read() {
            positions.place(Set(targets), on: hidden ? .left : .right)
            positionStore.write(positions)
            return
        }
        guard MenuBarInspector.isTrusted(prompt: false) else { return }
        while isMoving { try? await Task.sleep(for: .milliseconds(100)) }
        isMoving = true
        let savedCursor = CGEvent(source: nil)?.location ?? .zero
        for target in targets where coordinator.isVisible(target) && !coordinator.currentlyHidden.contains(target) {
            // An app can have several icons. Drag them one at a time, stopping once none are left
            // on the wrong side or a drag did not reduce their number.
            var remaining = Int.max
            while let count = await move(target, to: hidden ? .left : .right), count < remaining {
                remaining = count
            }
        }
        CGWarpMouseCursorPosition(savedCursor)
        isMoving = false
    }

    /// Drags the icon of `target` nearest to the archer over to `side`. Returns how many of its
    /// icons were on the other side before the drag, or `nil` if there were none.
    private func move(_ target: HideTarget, to side: MenuBarSide) async -> Int? {
        let items = inspector.snapshots()
        guard let toggle = items.first(where: { $0.pid == ownPID })?.frame else { return nil }
        let onOtherSide = items.filter {
            $0.pid != ownPID && MenuBarLayout.target(for: $0) == target && abs($0.frame.minY - toggle.minY) < 10
                && (side == .left ? $0.frame.midX > toggle.midX : $0.frame.midX < toggle.midX)
        }
        // Take the icon closest to the archer.
        let icon = side == .left
            ? onOtherSide.min(by: { $0.frame.minX < $1.frame.minX })
            : onOtherSide.max(by: { $0.frame.minX < $1.frame.minX })
        guard let icon else { return nil }
        await commandDrag(
            from: CGPoint(x: icon.frame.midX, y: icon.frame.midY),
            to: CGPoint(x: side == .left ? toggle.minX + 3 : toggle.maxX - 3, y: toggle.midY)
        )
        try? await Task.sleep(for: Const.moveSettleDelay)
        return onOtherSide.count
    }

    private func commandDrag(from start: CGPoint, to end: CGPoint) async {
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, start)
        try? await Task.sleep(for: .milliseconds(100))
        post(.leftMouseDown, start)
        try? await Task.sleep(for: .milliseconds(300))
        let steps = 30
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y))
            try? await Task.sleep(for: .milliseconds(12))
        }
        try? await Task.sleep(for: .milliseconds(100))
        post(.leftMouseUp, end)
    }

    // MARK: - Geometry

    /// Converts an AppKit screen point (origin at the bottom-left) to the AX space (top-left).
    private static func axPoint(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
    }

    private static func isInMenuBar(_ location: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            let frame = screen.frame
            let reserved = frame.maxY - screen.visibleFrame.maxY
            let height = reserved > 0 ? reserved : 24
            return location.x >= frame.minX && location.x < frame.maxX
                && location.y <= frame.maxY && location.y >= frame.maxY - height
        }
    }
}
