import AppKit

/// Reads menu bar item positions.
@MainActor
public protocol MenuBarInspecting {
    /// All status items in the menu bar, including Hanare's own.
    func snapshots() -> [MenuBarItemSnapshot]
}

/// Reads menu bar items through the Accessibility API.
///
/// On macOS 27 the whole menu bar is drawn by MenuBarAgent as a single window, so window lists
/// no longer reveal individual items. Accessibility still exposes each item with its frame.
public struct MenuBarInspector: MenuBarInspecting {
    public init() {}

    /// Whether Hanare is allowed to use the Accessibility API. Optionally asks the user.
    public static func isTrusted(prompt: Bool) -> Bool {
        // `kAXTrustedCheckOptionPrompt` is not concurrency-safe to reference, so use its value.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func snapshots() -> [MenuBarItemSnapshot] {
        NSWorkspace.shared.runningApplications.flatMap { app -> [MenuBarItemSnapshot] in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard let bar: AXUIElement = attribute(element, kAXExtrasMenuBarAttribute) else { return [] }
            let items: [AXUIElement] = attribute(bar, kAXChildrenAttribute) ?? []
            return items.compactMap { item in
                guard let frame = frame(of: item) else { return nil }
                return MenuBarItemSnapshot(
                    pid: app.processIdentifier,
                    bundleID: app.bundleIdentifier,
                    identifier: identifier(of: item),
                    frame: frame
                )
            }
        }
    }

    /// System items are hosting groups whose child carries the identifier.
    private func identifier(of item: AXUIElement) -> String? {
        if let identifier: String = attribute(item, kAXIdentifierAttribute) { return identifier }
        let children: [AXUIElement] = attribute(item, kAXChildrenAttribute) ?? []
        return children.lazy.compactMap { attribute($0, kAXIdentifierAttribute) as String? }.first
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
