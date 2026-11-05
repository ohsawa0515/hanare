import AppKit
import HanareCore

/// An app that has a menu bar icon macOS can turn off.
struct AppEntry: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage
    let isRunning: Bool

    var id: String { bundleID }
    var target: HideTarget { .app(bundleID: bundleID) }
}

/// Apps listed in System Settings > Menu Bar, read from the same setting Hanare changes.
@MainActor
enum AppCatalog {
    /// What the list depends on: the tracked apps and which of them run. Cheap to compare, so the
    /// list can be rebuilt only when it changes.
    static func fingerprint() -> [String]? {
        guard let groups = ownerGroups() else { return nil }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return groups.keys.sorted().map { id in groups[id, default: []].contains(where: running.contains) ? "\(id)+" : id }
    }

    /// Running apps first, then the rest by name. `nil` if macOS denies access to the setting.
    static func load() -> [AppEntry]? {
        guard let groups = ownerGroups() else { return nil }
        let running = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app in app.bundleIdentifier.map { ($0, app) } },
            uniquingKeysWith: { first, _ in first }
        )
        let ownID = Bundle.main.bundleIdentifier
        let entries = groups.compactMap { id, owners -> AppEntry? in
            guard !owners.contains(where: { $0 == ownID }) else { return nil }
            // An app's items can be owned by several processes; any of them can name it.
            let isRunning = owners.contains { running[$0] != nil }
            if let url = owners.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
                let name = FileManager.default.displayName(atPath: url.path).replacing(/\.app$/, with: "")
                return AppEntry(bundleID: id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path), isRunning: isRunning)
            }
            // Helper processes have no app bundle of their own; list them only while running.
            guard let app = owners.lazy.compactMap({ running[$0] }).first, let name = app.localizedName else { return nil }
            return AppEntry(bundleID: id, name: name, icon: app.icon ?? NSImage(), isRunning: true)
        }
        return entries.sorted {
            $0.isRunning != $1.isRunning ? $0.isRunning : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Canonical bundle ID of each tracked app, with every bundle ID that owns its items.
    private static func ownerGroups() -> [String: [String]]? {
        guard let canonical = AppVisibilityBackend()?.canonicalBundleIDs() else { return nil }
        return Dictionary(grouping: canonical.keys.sorted(), by: { canonical[$0]! })
    }
}
