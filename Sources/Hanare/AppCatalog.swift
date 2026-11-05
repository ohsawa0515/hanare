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
        guard let bundleIDs = AppVisibilityBackend()?.trackedBundleIDs() else { return nil }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return bundleIDs.sorted().map { running.contains($0) ? "\($0)+" : $0 }
    }

    /// Running apps first, then the rest by name. `nil` if macOS denies access to the setting.
    static func load() -> [AppEntry]? {
        guard let bundleIDs = AppVisibilityBackend()?.trackedBundleIDs() else { return nil }
        let running = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app in app.bundleIdentifier.map { ($0, app) } },
            uniquingKeysWith: { first, _ in first }
        )
        let ownID = Bundle.main.bundleIdentifier
        let entries = bundleIDs.compactMap { id -> AppEntry? in
            guard id != ownID else { return nil }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let name = FileManager.default.displayName(atPath: url.path).replacing(/\.app$/, with: "")
                return AppEntry(bundleID: id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path), isRunning: running[id] != nil)
            }
            // Helper processes have no app bundle of their own; list them only while running.
            guard let app = running[id], let name = app.localizedName else { return nil }
            return AppEntry(bundleID: id, name: name, icon: app.icon ?? NSImage(), isRunning: true)
        }
        return entries.sorted {
            $0.isRunning != $1.isRunning ? $0.isRunning : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
