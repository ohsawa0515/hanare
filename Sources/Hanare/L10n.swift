import Foundation
import HanareCore

/// Localized strings. Translations live in `Resources/Localizable.xcstrings`.
enum L10n {
    static var about: String { string("About Hanare") }
    static var settings: String { string("Settings…") }
    static var quit: String { string("Quit Hanare") }
    static var accessTitle: String { string("Allow Access to the Menu Bar Settings") }
    static var accessMessage: String {
        string("To hide and move icons, Hanare needs two files that macOS protects: the list of apps allowed in the menu bar and the menu bar order. Click Allow Access in each of the next two windows.")
    }
    static var allowAccessEllipsis: String { string("Allow Access…") }
    static var allowAccess: String { string("Allow Access") }
    static func choosePanelMessage(_ fileName: String) -> String {
        string("Select “\(fileName)”, then click Allow Access.")
    }
    static var showOnHover: String { string("Also show on hover") }
    static var cancel: String { string("Cancel") }

    static func name(of item: SystemItem) -> String {
        switch item {
        case .wifi: string("Wi-Fi")
        case .sound: string("Sound")
        case .battery: string("Battery")
        case .display: string("Display")
        case .bluetooth: string("Bluetooth")
        case .nowPlaying: string("Now Playing")
        case .inputMenu: string("Input Menu")
        }
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: ResourceBundle.strings)
    }
}
