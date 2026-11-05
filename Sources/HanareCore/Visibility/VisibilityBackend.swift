import Foundation

/// Reads and writes the visibility setting for one kind of ``HideTarget``.
///
/// Every backend writes through `cfprefsd` so that MenuBarAgent and Control Center are notified
/// and apply the change immediately, exactly like System Settings does.
public protocol VisibilityBackend {
    func handles(_ target: HideTarget) -> Bool
    /// The current value of the target's setting, or `nil` if the target cannot be controlled.
    func currentValue(of target: HideTarget) -> StoredValue?
    /// Whether the given setting value means the icon is shown.
    func isVisible(_ value: StoredValue) -> Bool
    /// Hides all given targets. Returns `false` if the setting could not be written.
    func hide(_ targets: [HideTarget]) -> Bool
    /// Restores the given items to their previous values.
    func restore(_ items: [HiddenItem]) -> Bool
    /// Whether the settings can be read at all. `false` when macOS denies access to them.
    var isAccessible: Bool { get }
}

extension VisibilityBackend {
    public var isAccessible: Bool { true }
}
