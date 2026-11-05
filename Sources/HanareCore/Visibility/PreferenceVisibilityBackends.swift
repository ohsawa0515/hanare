import Foundation

/// Hides Control Center modules (Wi-Fi, Sound, Display, Battery, ...) in the menu bar.
///
/// System Settings stores each module's menu bar visibility in the per-host `com.apple.controlcenter`
/// domain. `8` means "don't show"; other values (e.g. `2`, `18`) are kept and restored as they were.
public struct ControlCenterVisibilityBackend: VisibilityBackend {
    static let hiddenValue = 8
    private let domain = "com.apple.controlcenter" as CFString

    public init() {}

    public func handles(_ target: HideTarget) -> Bool {
        if case .controlCenter = target { true } else { false }
    }

    public func currentValue(of target: HideTarget) -> StoredValue? {
        guard case .controlCenter(let key) = target else { return nil }
        guard let value = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else {
            return .absent
        }
        return (value as? Int).map(StoredValue.int)
    }

    public func isVisible(_ value: StoredValue) -> Bool {
        value != .int(Self.hiddenValue)
    }

    public func hide(_ targets: [HideTarget]) -> Bool {
        write(targets.map { ($0, .int(Self.hiddenValue)) })
    }

    public func restore(_ items: [HiddenItem]) -> Bool {
        write(items.map { ($0.target, $0.previous) })
    }

    private func write(_ changes: [(HideTarget, StoredValue)]) -> Bool {
        for case (.controlCenter(let key), let value) in changes {
            CFPreferencesSetValue(key as CFString, value.propertyList, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}

/// Hides the input source menu by turning off `visible` in `com.apple.TextInputMenu`.
public struct InputMenuVisibilityBackend: VisibilityBackend {
    private let domain = "com.apple.TextInputMenu" as CFString
    private let key = "visible" as CFString

    public init() {}

    public func handles(_ target: HideTarget) -> Bool {
        target == .inputMenu
    }

    public func currentValue(of target: HideTarget) -> StoredValue? {
        guard target == .inputMenu else { return nil }
        guard let value = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            return .absent
        }
        return (value as? Bool).map(StoredValue.bool)
    }

    public func isVisible(_ value: StoredValue) -> Bool {
        value != .bool(false)
    }

    public func hide(_ targets: [HideTarget]) -> Bool {
        write(.bool(false))
    }

    public func restore(_ items: [HiddenItem]) -> Bool {
        guard let item = items.first(where: { $0.target == .inputMenu }) else { return true }
        return write(item.previous)
    }

    private func write(_ value: StoredValue) -> Bool {
        CFPreferencesSetValue(key, value.propertyList, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

extension StoredValue {
    /// The value to write back. `nil` removes the key.
    var propertyList: CFPropertyList? {
        switch self {
        case .bool(let value): value as CFBoolean
        case .int(let value): value as CFNumber
        case .absent: nil
        }
    }
}
