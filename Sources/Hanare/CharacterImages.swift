import AppKit
import HanareCore

/// The stages of the shot (射法八節) shown by the archer.
enum Pose: String, CaseIterable {
    /// 弓構え、弓に矢をつがえて構えた姿。アイコンを隠しているあいだの姿です。
    case yugamae
    /// 会 — full draw while the pointer is over the archer.
    case kai
    /// 離れ — the release that reveals the icons.
    case hanare
    /// 残心 — holding the form while icons are shown.
    case zanshin
}

@MainActor
enum CharacterImages {
    private static var cache: [String: NSImage] = [:]

    static func image(style: CharacterStyle, pose: Pose) -> NSImage? {
        switch style {
        case .male, .female: svgImage(named: "\(style.rawValue)-\(pose.rawValue)")
        case .simple: chevron(for: pose)
        }
    }

    private static func svgImage(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = ResourceBundle.bundle.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        image.accessibilityDescription = "Hanare"
        cache[name] = image
        return image
    }

    private static func chevron(for pose: Pose) -> NSImage? {
        let name = switch pose {
        case .yugamae: "chevron.left"
        case .kai: "chevron.left.2"
        case .hanare, .zanshin: "chevron.right"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: "Hanare")
    }
}

/// Resources live in the app bundle when packaged, and in the SwiftPM resource bundle during `swift run`.
enum ResourceBundle {
    static let bundle: Bundle = {
        if Bundle.main.url(forResource: "male-yugamae", withExtension: "svg") != nil { return .main }
        return .module
    }()
}
