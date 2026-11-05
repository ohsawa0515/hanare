import Foundation

/// System menu bar items that can be hidden.
public enum SystemItem: String, CaseIterable, Sendable {
    case wifi, sound, battery, display, bluetooth, nowPlaying, inputMenu

    /// `AXIdentifier` of the item in the menu bar. The input menu is recognized by its app instead.
    public var identifier: String? {
        switch self {
        case .wifi: "com.apple.menuextra.wifi"
        case .sound: "com.apple.menuextra.sound"
        case .battery: "com.apple.menuextra.battery"
        case .display: "com.apple.menuextra.display"
        case .bluetooth: "com.apple.menuextra.bluetooth"
        case .nowPlaying: "com.apple.menuextra.nowplaying"
        case .inputMenu: nil
        }
    }

    public var target: HideTarget {
        switch self {
        case .wifi: .controlCenter(key: "WiFi")
        case .sound: .controlCenter(key: "Sound")
        case .battery: .controlCenter(key: "Battery")
        case .display: .controlCenter(key: "Display")
        case .bluetooth: .controlCenter(key: "Bluetooth")
        case .nowPlaying: .controlCenter(key: "NowPlaying")
        case .inputMenu: .inputMenu
        }
    }
}
