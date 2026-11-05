import Foundation

/// Access to preferences stored in another app's group container through `cfprefsd`.
///
/// System Settings writes the per-app menu bar visibility into the `group.com.apple.controlcenter`
/// container. Writing to the same container source is what makes MenuBarAgent apply the change
/// without a restart; `defaults write <path>` uses a different source and is not observed.
/// The container-aware functions are private CoreFoundation SPI, resolved at runtime.
struct ContainerPreferences {
    private typealias CopyFn = @convention(c) (CFString, CFString, CFString, CFString, CFString) -> Unmanaged<CFPropertyList>?
    private typealias SetFn = @convention(c) (CFString, CFPropertyList?, CFString, CFString, CFString, CFString) -> Void
    private typealias SyncFn = @convention(c) (CFString, CFString, CFString, CFString) -> DarwinBoolean

    private let domain: CFString
    private let container: CFString
    private let copyValue: CopyFn
    private let setValue: SetFn
    private let synchronize: SyncFn

    init?(domain: String, container: URL) {
        guard let handle = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW),
              let copy = dlsym(handle, "_CFPreferencesCopyValueWithContainer"),
              let set = dlsym(handle, "_CFPreferencesSetValueWithContainer"),
              let sync = dlsym(handle, "_CFPreferencesSynchronizeWithContainer") else { return nil }
        self.domain = domain as CFString
        self.container = container.path as CFString
        copyValue = unsafeBitCast(copy, to: CopyFn.self)
        setValue = unsafeBitCast(set, to: SetFn.self)
        synchronize = unsafeBitCast(sync, to: SyncFn.self)
    }

    func value(forKey key: String) -> Any? {
        copyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)?.takeRetainedValue()
    }

    func set(_ value: Any?, forKey key: String) -> Bool {
        setValue(key as CFString, value as CFPropertyList?, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)
        return synchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container).boolValue
    }
}
