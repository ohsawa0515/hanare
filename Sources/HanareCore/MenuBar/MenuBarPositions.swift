import Foundation

/// The order macOS keeps for the right side of the menu bar.
///
/// MenuBarAgent stores one position per item in `TrailingItemPreferredPositions`, as the distance
/// from the right end of the menu bar: a larger value is further left. Keys look like
/// `status:<bundle ID>::<autosave name>` for status items and `module:<name>` for Control Center
/// modules. The table also keeps the positions of icons that are currently hidden.
public struct MenuBarPositions: Equatable, Sendable {
    public private(set) var entries: [String: Double]
    /// Hanare's own key, e.g. `status:Hanare::Hanare.toggle`.
    public let ownKey: String

    public init?(entries: [String: Double], ownAutosaveName: String) {
        guard let ownKey = entries.keys.first(where: { $0.hasSuffix("::" + ownAutosaveName) }) else { return nil }
        self.entries = entries
        self.ownKey = ownKey
    }

    private var ownPosition: Double { entries[ownKey] ?? 0 }

    /// The setting that controls the item behind `key`, or `nil` if it cannot be hidden.
    public static func target(forKey key: String) -> HideTarget? {
        if key.hasPrefix("module:") {
            let name = String(key.dropFirst("module:".count))
            return SystemItem.allCases.first { $0.target == .controlCenter(key: name) }?.target
        }
        guard key.hasPrefix("status:"), let end = key.range(of: "::") else { return nil }
        let bundleID = String(key[key.index(key.startIndex, offsetBy: "status:".count)..<end.lowerBound])
        if bundleID == MenuBarLayout.inputMenuBundleID { return .inputMenu }
        guard bundleID.contains("."), !bundleID.hasPrefix("com.apple.MenuBarAgent") else { return nil }
        return .app(bundleID: bundleID)
    }

    public func side(ofKey key: String) -> MenuBarSide {
        (entries[key] ?? 0) > ownPosition ? .left : .right
    }

    /// The sides on which each target has an icon. `isPresent` filters out entries left behind by
    /// apps that are not running.
    public func sides(where isPresent: (HideTarget) -> Bool) -> [HideTarget: Set<MenuBarSide>] {
        var result: [HideTarget: Set<MenuBarSide>] = [:]
        for key in entries.keys where key != ownKey {
            guard let target = Self.target(forKey: key), isPresent(target) else { continue }
            result[target, default: []].insert(side(ofKey: key))
        }
        return result
    }

    /// Targets on the left, ordered from the one nearest to the archer.
    public func targetsOnLeft(where isPresent: (HideTarget) -> Bool) -> [HideTarget] {
        var ordered: [HideTarget] = []
        for (key, _) in entries.filter({ $0.value > ownPosition }).sorted(by: { $0.value < $1.value }) {
            guard let target = Self.target(forKey: key), isPresent(target), !ordered.contains(target) else { continue }
            ordered.append(target)
        }
        return ordered
    }

    /// The smallest distance kept between neighboring positions. MenuBarAgent rewrites positions as
    /// whole or half points when the user drags, so values packed closer than that lose their order.
    static let minimumGap = 8.0

    /// Moves every icon of `targets` to `side` of the archer, right next to it. Positions are spread
    /// out again from there so each icon keeps a clear distance from its neighbors.
    public mutating func place(_ targets: Set<HideTarget>, on side: MenuBarSide) {
        let moving = entries.keys
            .filter { $0 != ownKey && Self.target(forKey: $0).map(targets.contains) == true && self.side(ofKey: $0) != side }
        guard !moving.isEmpty else { return }
        let moved = moving.sorted(by: byPosition)
        var order = entries.keys.filter { !moving.contains($0) }.sorted(by: byPosition)
        let ownIndex = order.firstIndex(of: ownKey)!
        order.insert(contentsOf: moved, at: side == .left ? ownIndex + 1 : ownIndex)
        spread(order, moved: Set(moved))
    }

    /// Whether some neighbors are closer than `minimumGap`, e.g. after earlier versions packed them.
    public var isCrowded: Bool {
        let values = entries.values.sorted()
        return zip(values, values.dropFirst()).contains { $1 - $0 < Self.minimumGap }
    }

    /// Spreads positions out without changing the order.
    public mutating func spreadOut() {
        spread(entries.keys.sorted(by: byPosition), moved: [])
    }

    private var byPosition: (String, String) -> Bool {
        { [entries] in (entries[$0] ?? 0, $0) < (entries[$1] ?? 0, $1) }
    }

    /// Walks from the right end, keeping each position unless it is too close to the previous one.
    /// Moved keys take the first free position after their neighbor.
    private mutating func spread(_ order: [String], moved movedSet: Set<String>) {
        var previous: Double?
        for key in order {
            let current = entries[key] ?? 0
            let value: Double
            if let previous {
                value = movedSet.contains(key) ? previous + Self.minimumGap : max(current, previous + Self.minimumGap)
            } else {
                value = movedSet.contains(key) ? Self.minimumGap : current
            }
            entries[key] = value
            previous = value
        }
    }
}

/// Reads and writes the menu bar order through `cfprefsd`, so MenuBarAgent moves icons right away.
/// The file is in a protected group container; Hanare can use it once the user picks it.
public struct MenuBarPositionStore {
    private static let key = "TrailingItemPreferredPositions"
    private let preferences: ContainerPreferences
    private let ownAutosaveName: String

    public static let domain = "com.apple.MenuBar"
    public static var containerURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Group Containers/com.apple.MenuBar")
    }

    public init?(ownAutosaveName: String) {
        guard let preferences = ContainerPreferences(domain: Self.domain, container: Self.containerURL) else { return nil }
        self.preferences = preferences
        self.ownAutosaveName = ownAutosaveName
    }

    /// The current order, or `nil` if it cannot be read or Hanare's icon is not in it yet.
    public func read() -> MenuBarPositions? {
        guard let raw = preferences.value(forKey: Self.key) as? [String: Any] else { return nil }
        let entries = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        return MenuBarPositions(entries: entries, ownAutosaveName: ownAutosaveName)
    }

    @discardableResult
    public func write(_ positions: MenuBarPositions) -> Bool {
        guard var raw = preferences.value(forKey: Self.key) as? [String: Any] else { return false }
        for (key, value) in positions.entries { raw[key] = value }
        return preferences.set(raw, forKey: Self.key)
    }
}
