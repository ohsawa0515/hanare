import Foundation
import os

/// Persists the items Hanare has hidden, so they can be restored even after a crash.
public struct HiddenItemsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "hiddenItems") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [HiddenItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([HiddenItem].self, from: data)) ?? []
    }

    public func save(_ items: [HiddenItem]) {
        if items.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Hides and restores targets through the matching ``VisibilityBackend``.
///
/// Only targets that are currently visible are hidden, and only what Hanare hid is ever restored,
/// so icons the user turned off in System Settings stay off. The hidden list is saved before any
/// setting is written.
@MainActor
public final class VisibilityController {
    private let backends: [any VisibilityBackend]
    private let store: HiddenItemsStore
    private let logger = Logger(subsystem: "io.github.ohsawa0515.Hanare", category: "visibility")

    /// Hidden items, ordered from the one nearest to Hanare's icon.
    public private(set) var hiddenItems: [HiddenItem]

    public init(backends: [any VisibilityBackend], store: HiddenItemsStore) {
        self.backends = backends
        self.store = store
        hiddenItems = store.load()
    }

    /// Hides the given targets, ordered from the one nearest to Hanare's icon.
    /// Returns the targets that were actually hidden.
    @discardableResult
    public func hide(_ targets: [HideTarget]) -> [HideTarget] {
        let alreadyHidden = Set(hiddenItems.map(\.target))
        var newItems: [HiddenItem] = []
        for target in targets where !alreadyHidden.contains(target) {
            guard let backend = backend(for: target),
                  let current = backend.currentValue(of: target),
                  backend.isVisible(current) else {
                logger.info("Skipping \(String(describing: target), privacy: .public)")
                continue
            }
            newItems.append(HiddenItem(target: target, previous: current))
        }
        guard !newItems.isEmpty else { return [] }

        hiddenItems += newItems
        store.save(hiddenItems)
        var hidden: [HideTarget] = []
        for (index, backend) in backends.enumerated() {
            let targets = newItems.map(\.target).filter(backend.handles)
            guard !targets.isEmpty else { continue }
            if backend.hide(targets) {
                hidden += targets
            } else {
                logger.error("Failed to hide with backend #\(index)")
            }
        }
        return hidden
    }

    /// Restores one hidden target.
    public func restore(_ target: HideTarget) {
        guard let item = hiddenItems.first(where: { $0.target == target }) else { return }
        restore([item])
    }

    /// Restores every hidden target.
    public func restoreAll() {
        restore(hiddenItems)
    }

    private func restore(_ items: [HiddenItem]) {
        var restored: Set<HideTarget> = []
        for backend in backends {
            let mine = items.filter { backend.handles($0.target) }
            guard !mine.isEmpty else { continue }
            if backend.restore(mine) {
                restored.formUnion(mine.map(\.target))
            } else {
                logger.error("Failed to restore \(mine.count) item(s)")
            }
        }
        hiddenItems.removeAll { restored.contains($0.target) }
        store.save(hiddenItems)
    }

    /// Whether the target's icon is currently shown, according to its setting.
    public func isVisible(_ target: HideTarget) -> Bool {
        guard let backend = backend(for: target), let value = backend.currentValue(of: target) else { return false }
        return backend.isVisible(value)
    }

    /// Targets whose settings macOS does not let Hanare read.
    public func inaccessible(_ targets: [HideTarget]) -> [HideTarget] {
        targets.filter { backend(for: $0)?.isAccessible == false }
    }

    private func backend(for target: HideTarget) -> (any VisibilityBackend)? {
        backends.first { $0.handles(target) }
    }
}
