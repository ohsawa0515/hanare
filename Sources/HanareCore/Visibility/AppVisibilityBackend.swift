import Foundation

/// Hides app status items by turning them off in System Settings > Menu Bar.
///
/// The setting lives in `group.com.apple.controlcenter` under `trackedApplications`,
/// with one `isAllowed` flag per app. Visibility can only be controlled per app,
/// so every status item of the app is hidden together.
public struct AppVisibilityBackend: VisibilityBackend {
    private static let key = "trackedApplications"
    private let preferences: ContainerPreferences

    public init?() {
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Group Containers/group.com.apple.controlcenter")
        guard let preferences = ContainerPreferences(domain: "group.com.apple.controlcenter", container: container) else { return nil }
        self.preferences = preferences
    }

    public func handles(_ target: HideTarget) -> Bool {
        if case .app = target { true } else { false }
    }

    public func currentValue(of target: HideTarget) -> StoredValue? {
        guard case .app(let bundleID) = target, let entries = readEntries() else { return nil }
        return TrackedApplications.allowedStates(in: entries)[bundleID].map(StoredValue.bool)
    }

    public func isVisible(_ value: StoredValue) -> Bool {
        value != .bool(false)
    }

    /// macOS protects other apps' group containers. The read is denied until the user picks the file.
    public var isAccessible: Bool {
        readEntries() != nil
    }

    /// Maps every bundle ID that owns status items to the one Hanare uses for its app. An app's
    /// items can be owned by several processes that share a single on/off switch.
    public func canonicalBundleIDs() -> [String: String]? {
        readEntries().map(TrackedApplications.canonicalOwners)
    }

    public func hide(_ targets: [HideTarget]) -> Bool {
        write(targets.compactMap(Self.bundleID).map { ($0, false) })
    }

    public func restore(_ items: [HiddenItem]) -> Bool {
        write(items.compactMap { item in
            guard let bundleID = Self.bundleID(of: item.target), case .bool(let allowed) = item.previous else { return nil }
            return (bundleID, allowed)
        })
    }

    private func write(_ changes: [(bundleID: String, allowed: Bool)]) -> Bool {
        guard !changes.isEmpty, var entries = readEntries() else { return changes.isEmpty }
        for allowed in [true, false] {
            let ids = Set(changes.filter { $0.allowed == allowed }.map(\.bundleID))
            entries = TrackedApplications.settingAllowed(allowed, for: ids, in: entries)
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0) else {
            return false
        }
        return preferences.set(data, forKey: Self.key)
    }

    private func readEntries() -> [Any]? {
        guard let data = preferences.value(forKey: Self.key) as? Data else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any]
    }

    private static func bundleID(of target: HideTarget) -> String? {
        if case .app(let bundleID) = target { bundleID } else { nil }
    }
}

/// Interprets the `trackedApplications` value.
///
/// It is an encoded Swift dictionary: a flat array alternating keys (`{bundle: {_0: <id>}}`) and
/// values (`{location, menuItemLocations: [{bundle: {_0: <id>}}], isAllowed}`). The bundle IDs in
/// `menuItemLocations` are the processes that own the status items, which can differ from the app
/// itself (e.g. Docker Desktop). Unknown fields are preserved as-is.
enum TrackedApplications {
    static func allowedStates(in entries: [Any]) -> [String: Bool] {
        var states: [String: Bool] = [:]
        for case let entry as [String: Any] in entries {
            guard let allowed = entry["isAllowed"] as? Bool else { continue }
            for bundleID in menuItemBundleIDs(of: entry) { states[bundleID] = allowed }
        }
        return states
    }

    static func canonicalOwners(in entries: [Any]) -> [String: String] {
        var result: [String: String] = [:]
        for case let entry as [String: Any] in entries where entry["isAllowed"] is Bool {
            let owners = menuItemBundleIDs(of: entry).sorted()
            guard let canonical = owners.first else { continue }
            for owner in owners { result[owner] = canonical }
        }
        return result
    }

    static func settingAllowed(_ allowed: Bool, for bundleIDs: Set<String>, in entries: [Any]) -> [Any] {
        guard !bundleIDs.isEmpty else { return entries }
        return entries.map { element in
            guard var entry = element as? [String: Any], entry["isAllowed"] is Bool,
                  !bundleIDs.isDisjoint(with: menuItemBundleIDs(of: entry)) else { return element }
            entry["isAllowed"] = allowed
            return entry
        }
    }

    private static func menuItemBundleIDs(of entry: [String: Any]) -> Set<String> {
        let locations = entry["menuItemLocations"] as? [[String: Any]] ?? []
        return Set(locations.compactMap { ($0["bundle"] as? [String: Any])?["_0"] as? String })
    }
}
