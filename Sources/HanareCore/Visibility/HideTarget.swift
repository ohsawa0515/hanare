import Foundation

/// A menu bar icon that Hanare can hide, identified by the setting that controls its visibility.
public enum HideTarget: Hashable, Codable, Sendable {
    /// A third-party (or Apple) app's status item, toggled per app in System Settings > Menu Bar.
    case app(bundleID: String)
    /// A Control Center module such as Wi-Fi or Sound, keyed by its preference name (e.g. `WiFi`).
    case controlCenter(key: String)
    /// The input source menu (e.g. Google Japanese Input).
    case inputMenu
}

/// The value a visibility setting had before Hanare changed it, so that it can be restored exactly.
public enum StoredValue: Hashable, Codable, Sendable {
    case bool(Bool)
    case int(Int)
    /// The setting did not exist.
    case absent
}

/// A target that Hanare has hidden, together with the value to restore.
public struct HiddenItem: Hashable, Codable, Sendable {
    public let target: HideTarget
    public let previous: StoredValue

    public init(target: HideTarget, previous: StoredValue) {
        self.target = target
        self.previous = previous
    }
}
