import CoreGraphics
import Foundation

/// A menu bar item as seen through the Accessibility API. Frames use the AX coordinate space
/// (origin at the top-left of the main display, y pointing down).
public struct MenuBarItemSnapshot: Equatable, Sendable {
    public let pid: pid_t
    public let bundleID: String?
    /// `AXIdentifier` of the item, e.g. `com.apple.menuextra.wifi` for system items.
    public let identifier: String?
    public let frame: CGRect

    public init(pid: pid_t, bundleID: String?, identifier: String?, frame: CGRect) {
        self.pid = pid
        self.bundleID = bundleID
        self.identifier = identifier
        self.frame = frame
    }
}

public enum MenuBarSide: Hashable, Sendable {
    case left, right
}

/// Works out on which side of Hanare's icon each hideable item sits, and what a drag changed.
public enum MenuBarLayout {
    static let inputMenuBundleID = "com.apple.TextInputMenuAgent"

    /// The setting that controls the item, or `nil` if it cannot be hidden (e.g. the clock).
    public static func target(for item: MenuBarItemSnapshot) -> HideTarget? {
        if let identifier = item.identifier, let system = SystemItem.allCases.first(where: { $0.identifier == identifier }) {
            return system.target
        }
        if item.bundleID == inputMenuBundleID {
            return .inputMenu
        }
        guard let bundleID = item.bundleID, !bundleID.hasPrefix("com.apple.MenuBarAgent") else { return nil }
        return .app(bundleID: bundleID)
    }

    /// The sides on which each target has an icon, relative to Hanare's icon.
    public static func sides(
        of items: [MenuBarItemSnapshot],
        relativeTo toggle: CGRect,
        ownPID: pid_t
    ) -> [HideTarget: Set<MenuBarSide>] {
        var result: [HideTarget: Set<MenuBarSide>] = [:]
        for item in items where item.pid != ownPID && abs(item.frame.minY - toggle.minY) < 10 {
            guard let target = target(for: item) else { continue }
            result[target, default: []].insert(item.frame.midX < toggle.midX ? .left : .right)
        }
        return result
    }

    /// The hideable target whose icon is under `point`, ignoring Hanare's own items.
    public static func target(at point: CGPoint, in items: [MenuBarItemSnapshot], ownPID: pid_t) -> HideTarget? {
        items.first { $0.pid != ownPID && $0.frame.insetBy(dx: -2, dy: -2).contains(point) }.flatMap(target(for:))
    }

    /// Which side of Hanare's icon a dropped icon ended up on. An app can have several icons, so
    /// the one nearest to where the mouse was released is taken to be the dragged one.
    public static func side(
        of target: HideTarget,
        droppedNear point: CGPoint,
        in items: [MenuBarItemSnapshot],
        relativeTo toggle: CGRect,
        ownPID: pid_t
    ) -> MenuBarSide? {
        let icons = items.filter {
            $0.pid != ownPID && abs($0.frame.minY - toggle.minY) < 10 && Self.target(for: $0) == target
        }
        guard let dropped = icons.min(by: { abs($0.frame.midX - point.x) < abs($1.frame.midX - point.x) }) else { return nil }
        return dropped.frame.midX < toggle.midX ? .left : .right
    }
}
