import Foundation
import Observation

/// The archer shown in the menu bar.
public enum CharacterStyle: String, CaseIterable, Sendable {
    case male
    case female
    /// A plain chevron instead of a character.
    case simple
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
    }

    @ObservationIgnored private let defaults: UserDefaults

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

    public func isHidden(_ target: HideTarget) -> Bool {
        hiddenTargets.contains(target)
    }

    public func setHidden(_ hidden: Bool, for target: HideTarget) {
        if hidden, !isHidden(target) {
            hiddenTargets.append(target)
        } else if !hidden {
            hiddenTargets.removeAll { $0 == target }
        }
    }

    /// Chooses or clears many targets at once.
    public func setHidden(_ hidden: Bool, for targets: [HideTarget]) {
        if hidden {
            hiddenTargets += targets.filter { !isHidden($0) }
        } else {
            hiddenTargets.removeAll { targets.contains($0) }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        character = defaults.string(forKey: Key.character).flatMap(CharacterStyle.init) ?? .male
        hiddenTargets = defaults.data(forKey: Key.hiddenTargets)
            .flatMap { try? JSONDecoder().decode([HideTarget].self, from: $0) } ?? []
        autoCollapseDelay = defaults.object(forKey: Key.autoCollapseDelay) as? TimeInterval ?? 10
    }
}
