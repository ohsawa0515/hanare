import Foundation
import Testing
@testable import HanareCore

/// In-memory backend for app targets.
final class FakeBackend: VisibilityBackend {
    var values: [HideTarget: StoredValue]
    var failWrites = false
    /// Targets in the order they were restored.
    var restoredOrder: [HideTarget] = []

    init(values: [HideTarget: StoredValue]) {
        self.values = values
    }

    func handles(_ target: HideTarget) -> Bool { values.keys.contains(target) }
    func currentValue(of target: HideTarget) -> StoredValue? { values[target] }
    func isVisible(_ value: StoredValue) -> Bool { value != .bool(false) }

    func hide(_ targets: [HideTarget]) -> Bool {
        guard !failWrites else { return false }
        for target in targets { values[target] = .bool(false) }
        return true
    }

    func restore(_ items: [HiddenItem]) -> Bool {
        guard !failWrites else { return false }
        for item in items {
            values[item.target] = item.previous
            restoredOrder.append(item.target)
        }
        return true
    }
}

@MainActor
struct VisibilityControllerTests {
    private let shown = HideTarget.app(bundleID: "com.example.shown")
    private let userHidden = HideTarget.app(bundleID: "com.example.userHidden")

    private func makeStore() -> HiddenItemsStore {
        HiddenItemsStore(defaults: UserDefaults(suiteName: "HanareTests-\(UUID().uuidString)")!)
    }

    @Test func hidesOnlyVisibleTargetsAndRestoresThem() {
        let backend = FakeBackend(values: [shown: .bool(true), userHidden: .bool(false)])
        let controller = VisibilityController(backends: [backend], store: makeStore())

        let hidden = controller.hide([shown, userHidden])
        #expect(hidden == [shown])
        #expect(backend.values[shown] == .bool(false))

        controller.restoreAll()
        #expect(backend.values[shown] == .bool(true))
        #expect(backend.values[userHidden] == .bool(false))
        #expect(controller.hiddenItems.isEmpty)
    }

    @Test func persistsHiddenItemsForCrashRecovery() {
        let store = makeStore()
        let backend = FakeBackend(values: [shown: .bool(true)])
        VisibilityController(backends: [backend], store: store).hide([shown])

        let relaunched = VisibilityController(backends: [backend], store: store)
        #expect(relaunched.hiddenItems == [HiddenItem(target: shown, previous: .bool(true))])
        relaunched.restoreAll()
        #expect(backend.values[shown] == .bool(true))
        #expect(store.load().isEmpty)
    }

    @Test func keepsItemsWhenRestoreFails() {
        let backend = FakeBackend(values: [shown: .bool(true)])
        let controller = VisibilityController(backends: [backend], store: makeStore())
        controller.hide([shown])

        backend.failWrites = true
        controller.restoreAll()
        #expect(controller.hiddenItems.count == 1)
    }

    @Test func dropsTargetsAFailedHideLeftVisible() {
        let backend = FakeBackend(values: [shown: .bool(true)])
        backend.failWrites = true
        let controller = VisibilityController(backends: [backend], store: makeStore())

        #expect(controller.hide([shown]).isEmpty)
        #expect(controller.hiddenItems.isEmpty)
    }

    @Test func hidesAgainWhenAJournaledTargetIsVisible() {
        let backend = FakeBackend(values: [shown: .bool(true)])
        let controller = VisibilityController(backends: [backend], store: makeStore())
        controller.hide([shown])
        backend.values[shown] = .bool(true)  // shown again behind Hanare's back

        #expect(controller.hide([shown]) == [shown])
        #expect(backend.values[shown] == .bool(false))
        #expect(controller.hiddenItems == [HiddenItem(target: shown, previous: .bool(true))])
    }
}

@MainActor
struct HidingCoordinatorPeekTests {
    private let always = HideTarget.app(bundleID: "com.example.always")
    private let often = HideTarget.app(bundleID: "com.example.often")

    private func makeCoordinator() -> (HidingCoordinator, FakeBackend) {
        let backend = FakeBackend(values: [always: .bool(true), often: .bool(true)])
        let store = HiddenItemsStore(defaults: UserDefaults(suiteName: "HanareTests-\(UUID().uuidString)")!)
        let coordinator = HidingCoordinator(visibility: VisibilityController(backends: [backend], store: store))
        coordinator.targets = { [always, often] }
        coordinator.hoverTargets = { [often] }
        return (coordinator, backend)
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(400)) }

    @Test func peekShowsOnlyHoverTargetsAndEndPeekHidesThemAgain() async {
        let (coordinator, backend) = makeCoordinator()
        coordinator.collapse()

        coordinator.peek()
        #expect(coordinator.state == .peeking)
        await settle()
        #expect(backend.values[often] == .bool(true))
        #expect(backend.values[always] == .bool(false))

        coordinator.endPeek()
        #expect(coordinator.state == .collapsed)
        #expect(backend.values[often] == .bool(false))
    }

    @Test func clickWhilePeekingShowsEverything() async {
        let (coordinator, backend) = makeCoordinator()
        coordinator.collapse()
        coordinator.peek()
        await settle()

        coordinator.toggle()
        #expect(coordinator.state == .expanded)
        await settle()
        #expect(backend.values[always] == .bool(true))
    }

    @Test func peekDoesNothingWithoutHoverTargets() {
        let (coordinator, _) = makeCoordinator()
        coordinator.hoverTargets = { [] }
        coordinator.collapse()
        coordinator.peek()
        #expect(coordinator.state == .collapsed)
    }
}

@MainActor
struct RevealOrderTests {
    @Test func keepsTheChosenOrderAfterAPeek() async {
        let first = HideTarget.app(bundleID: "com.example.first")
        let second = HideTarget.app(bundleID: "com.example.second")
        let backend = FakeBackend(values: [first: .bool(true), second: .bool(true)])
        let store = HiddenItemsStore(defaults: UserDefaults(suiteName: "HanareTests-\(UUID().uuidString)")!)
        let controller = VisibilityController(backends: [backend], store: store)
        let coordinator = HidingCoordinator(visibility: controller)
        coordinator.targets = { [first, second] }
        coordinator.hoverTargets = { [first] }

        coordinator.collapse()
        coordinator.peek()
        try? await Task.sleep(for: .milliseconds(300))
        coordinator.endPeek()

        #expect(controller.hiddenItems.map(\.target) == [second, first])
        backend.restoredOrder = []
        coordinator.expand()
        try? await Task.sleep(for: .milliseconds(500))
        // The icon chosen first is revealed first.
        #expect(backend.restoredOrder == [first, second])
    }
}
