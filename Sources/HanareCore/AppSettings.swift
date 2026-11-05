import Foundation
import Observation

/// The archer shown in the menu bar.
public enum CharacterStyle: String, CaseIterable, Sendable {
    case male
    case female
    /// A plain chevron instead of a character.
    case simple
}

/// The language of Hanare's own text. English unless the user chooses otherwise.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case japanese = "ja"

    /// The `UserDefaults` key, also read by the localization code outside of ``AppSettings``.
    public static let defaultsKey = "language"

    public static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init) ?? .english
    }
}

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
public final class AppSettings {
    public static let autoCollapseChoices: [TimeInterval] = [0, 5, 10, 30, 60]

    private enum Key {
        static let character = "character"
        static let autoCollapseDelay = "autoCollapseDelay"
        static let hiddenTargets = "hideTargets"
        static let hoverTargets = "hoverTargets"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: AppLanguage.defaultsKey) }
    }

    public var character: CharacterStyle {
        didSet { defaults.set(character.rawValue, forKey: Key.character) }
    }

    /// Seconds before revealed icons are hidden again. `0` means never.
    public var autoCollapseDelay: TimeInterval {
        didSet { defaults.set(autoCollapseDelay, forKey: Key.autoCollapseDelay) }
    }

    /// The icons to hide, in the order they were chosen.
    public private(set) var hiddenTargets: [HideTarget] {
        didSet { defaults.set(try? JSONEncoder().encode(hiddenTargets), forKey: Key.hiddenTargets) }
    }

    /// Hidden icons that appear while the pointer is over the archer, without clicking.
    public private(set) var hoverTargets: [HideTarget] {
        didSet { defaults.set(try? JSONEncoder().encode(hoverTargets), forKey: Key.hoverTargets) }
    }

    public func isShownOnHover(_ target: HideTarget) -> Bool {
        hoverTargets.contains(target)
    }

    public func setShownOnHover(_ shown: Bool, for target: HideTarget) {
        if shown, !isShownOnHover(target) {
            hoverTargets.append(target)
        } else if !shown {
            hoverTargets.removeAll { $0 == target }
        }
    }

    public func isHidden(_ target: HideTarget) -> Bool {
        hiddenTargets.contains(target)
    }

    public func setHidden(_ hidden: Bool, for target: HideTarget) {
        if hidden, !isHidden(target) {
            hiddenTargets.append(target)
        } else if !hidden {
            hiddenTargets.removeAll { $0 == target }
            setShownOnHover(false, for: target)
        }
    }

    /// Chooses or clears many targets at once.
    public func setHidden(_ hidden: Bool, for targets: [HideTarget]) {
        if hidden {
            hiddenTargets += targets.filter { !isHidden($0) }
        } else {
            hiddenTargets.removeAll { targets.contains($0) }
            hoverTargets.removeAll { targets.contains($0) }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        character = defaults.string(forKey: Key.character).flatMap(CharacterStyle.init) ?? .male
        hiddenTargets = defaults.data(forKey: Key.hiddenTargets)
            .flatMap { try? JSONDecoder().decode([HideTarget].self, from: $0) } ?? []
        language = AppLanguage.stored(in: defaults)
        hoverTargets = defaults.data(forKey: Key.hoverTargets)
            .flatMap { try? JSONDecoder().decode([HideTarget].self, from: $0) } ?? []
        autoCollapseDelay = defaults.object(forKey: Key.autoCollapseDelay) as? TimeInterval ?? 10
    }
}
